# frozen_string_literal: true

require 'sinatra'
require 'slim'
require 'sassc'
require 'securerandom'
require 'rmagick'
require_relative 'models'
require_relative 'utils'

include Utils

if settings.development?
  require 'rack-livereload'
  require 'sinatra/reloader'

  use Rack::LiveReload, source: :vendored
  Thread.new do
    system('bundle exec guard')
  end

  also_reload 'models.rb', 'utils.rb'
end

enable :sessions

auth_needed = %w[/listing/new /message]
ignored_paths = %w[/style.css /favicon.ico /auth-needed]
auth_paths = %w[/login /register /auth-needed]

def forbidden
  status 403
  slim :'generic/403'
end

def unauthorized
  status 401
  slim :'generic/401'
end

def too_many_requests(route = '/')
  status 429
  slim :'generic/429', locals: { route: route }
end

not_found do
  slim :'generic/404'
end

RATE_LIMITS = Hash.new(Hash.new(0))

# Make sure user is allowed to see page if not logged in
before do
  status temp_session(:status_code) if session[:status_code]
  return if ignored_paths.include? request.path_info

  if !current_user && auth_needed.map { |path| request.path_info.start_with?(path) }.any?
    session[:return_to] = request.fullpath
    session[:status_code] = 403
    redirect '/auth-needed'
  end
  # If the user has gone and done something else than logging in or registering,
  # make sure to not return back after logging/registering in later
  (auth_paths.include? request.path_info) || session.delete(:return_to)
end

get '/' do
  slim :index
end

# Show page prompting user to login if authentication is needed
get '/auth-needed' do
  unauthorized
end

# Compile and serve project sass
get '/style.css' do
  scss :'scss/style', style: :compressed
end

# Shows the form to create a new listing
get '/listing/new' do
  slim :'listing/edit_or_create'
end

# Create a new listing
# @param title [String] The title of the listing
# @param content [String] The body of the listing
# @param price [Integer] The price of the listing
# @param postal_code [String] The postal code for the listing
# @param cover [Tempfile] The cover image of the ad
# @param tags [Array<Tag>] The tags of the ad
#
# @see Listing#create
post '/listing/new' do
  return too_many_requests('/listing/new') unless Time.now.to_f - RATE_LIMITS[:create_listing][current_user.id] > 10

  error = nil

  postal_code = params[:postal_code].delete(' ').delete('-').to_i
  error = 'Postnummret måste vara 5 siffror' unless postal_code.to_s.length == 5
  error = 'Priset måste vara positivt' if params[:price].to_i.negative?
  error = 'Priset får inte vara mer än 1000 miljarder kr' if params[:price].to_i > 1e12
  error = 'Du måste ange ett postnummer' if params[:postal_code].empty?
  error = 'Du måste ange en beskrivning' if params[:content].empty?
  error = 'Du måste ange en titel' if params[:title].empty?
  error = 'Titeln får inte vara längre än 64 tecken' if params[:title].length > 64
  error = 'Postnummret måste vara ett riktigt postnummer' if postal_codes[postal_code.to_s].nil?

  if error
    session[:old_data] = params
    session[:form_error] = error
    return redirect '/listing/new'
  end

  new_name = nil

  if params[:cover]
    imagefile = params[:cover][:tempfile]
    # filename = params[:cover][:filename]
    # extension = filename.split('.').last
    new_name = "#{SecureRandom.uuid}.jpg"
    data = imagefile.read

    new_file_name = File.join(File.dirname(__FILE__), "userimgs/#{new_name}")

    image = Magick::Image.from_blob(data).first
    image.format = 'jpeg'
    File.open(new_file_name, 'wb') do |f|
      image.resize_to_fit(720 * 4, 320 * 4).write(f) { self.quality = 70 }
    end
  end

  listing = Listing.create(
    params[:title], params[:content], params[:price].to_i,
    current_user.id, postal_code, new_name, params[:tags] || []
  )
  RATE_LIMITS[:create_listing][current_user.id] = Time.now.to_f
  redirect "/listing/#{listing.id}"
end

# Shows for to edit an listing
# @param :id [Integer] The id of the listing to edit
get '/listing/:id/edit' do
  listing = Listing.find_by_id(params[:id])
  slim :'listing/edit_or_create', locals: { listing: listing }
end

# Edit an listing
# @param :id [Integer] The id of the listing to edit
# @param title [String] The title of the listing
# @param content [String] The body of the listing
# @param price [Integer] The price of the listing
# @param postal_code [String] The postal code for the listing
# @param cover [Tempfile] The cover image of the listing
# @param tags [Array<Tag>] The tags of the listing
#
# @see Listing#update
post '/listing/:id/update' do
  listing = Listing.find_by_id(params[:id])

  error = nil

  postal_code = params[:postal_code].delete(' ').delete('-').to_i
  error = 'Postnummret måste vara 5 siffror' unless postal_code.to_s.length == 5
  error = 'Priset måste vara positivt' if params[:price].to_i.negative?
  error = 'Priset får inte vara mer än 1000 miljarder kr' if params[:price].to_i > 1e12
  error = 'Du måste ange ett postnummer' if params[:postal_code].empty?
  error = 'Du måste ange en beskrivning' if params[:content].empty?
  error = 'Du måste ange en titel' if params[:title].empty?
  error = 'Titeln får inte vara längre än 64 tecken' if params[:title].length > 64
  error = 'Postnummret måste vara ett riktigt postnummer' if postal_codes[postal_code.to_s].nil?

  if error
    session[:old_data] = params
    session[:form_error] = error
    return redirect '/listing/new'
  end

  new_name = nil

  if params[:cover]
    File.delete("userimgs/#{listing.image_name}") if listing.image_name
    imagefile = params[:cover][:tempfile]
    # filename = params[:cover][:filename]
    # extension = filename.split('.').last
    new_name = "#{SecureRandom.uuid}.jpg"
    data = imagefile.read

    new_file_name = "userimgs/#{new_name}"

    image = Magick::Image.from_blob(data).first
    image.format = 'jpeg'
    File.open(new_file_name, 'wb') do |f|
      image.resize_to_fit(720 * 4, 320 * 4).write(f) { self.quality = 70 }
    end
  end

  listing.update(
    params[:title], params[:content], params[:price].to_i,
    current_user.id, postal_code, new_name || listing.image_name, params[:tags]
  )

  redirect "/listing/#{listing.id}"
end

# Shows all availible tags, and allows admins to create new tags
get '/tags' do
  slim :'listing/tags'
end

# Create a new tag if the user is an admin
# @param name [String] The name of the tag
#
# @see Tag#create
post '/tags' do
  return unauthorized unless current_user.admin

  session[:form_error] = "Taggen '#{params[:name]}' finns redan" unless Tag.create(params[:name])
  redirect '/tags'
end

# Shows an listing
# @param :id [Integer] The id of the listing to show
get '/listing/:id' do
  listing = Listing.find_by_id(params[:id])
  raise Sinatra::NotFound unless listing

  slim :'listing/view', locals: { listing: listing }
end

# Fetches an image for an listing
# @param :filename [String] The filename for the processed listing image
get '/userimg/:filename' do
  send_file File.join(File.dirname(__FILE__), "userimgs/#{params[:filename]}")
end

# Deletes an listing
# @param :id [String] The id of the listing to delete
post '/listing/:id/delete' do
  listing = Listing.find_by_id(params[:id])
  raise Sinatra::NotFound unless listing

  return forbidden unless listing.seller == current_user || current_user.admin

  listing.delete
  session[:msg] = 'Annonsen har raderats'
  session[:success] = true
  redirect '/'
end

# Shows the login form
get '/login' do
  return redirect '/' if current_user

  slim :'user/login'
end

# Logs out a user
get '/logout' do
  session.clear
  redirect '/'
end

# Shows the form to register a new user
get '/register' do
  return redirect '/' if current_user

  slim :'user/register'
end

# Searches for listings according to the specified filters
# @param query [String] The query to search for
# @param tags [Array<Integer>] The tags to search for
# @param min_price [Integer] The minimum price to search for
# @param max_price [Integer] The maximum price to search for
# @param max_distance [Integer] The maximum distance to search for
#
# @see Listing#search
get '/search' do
  listings = Listing.search((params[:query] || '').split(' '))
  listings.keep_if do |listing|
    filters = []
    filters << (listing.price <= params[:max_price].to_i if params[:max_price] && !params[:max_price].empty?)
    filters << (listing.price >= params[:min_price].to_i if params[:min_price] && !params[:min_price].empty?)
    filters << ((if params[:tags]
                   (params[:tags].all? do |tag_id|
                      listing.tags.include?(tag_id.to_i)
                    end)
                 end))
    if params[:max_distance] && params[:max_distance].to_i != 100
      filters << ((postal_code_distance(listing.postal_code, current_user.postal_code) || 100) <= params[:max_distance].to_i)
    end
    filters.reject!(&:nil?)
    filters.all?
  end
  slim :'listing/search', locals: { listings: listings }
end

# Shows a user's profile page
# @param :id [String] The id of the user to show
get '/user/:id' do
  user = User.find_by_id(params[:id])
  raise Sinatra::NotFound unless user

  slim :'user/profile', locals: { user: user }
end

# Shows the conversation between two users, the seller of an listing and the current_user
# @param :id [Integer] The id of the listing to show the conversation with
get '/message/:id' do
  listing = Listing.find_by_id(params[:id])
  raise Sinatra::NotFound unless listing
  return forbidden unless listing.seller != current_user

  slim :'user/messages', locals: { to: listing.seller, listing: listing, messages: Message.conversation(current_user, listing) }
end

# Shows the conversation between two users, the listing for which the conversation takes place and a customer
# @param :id [Integer] The id of the listing to show the conversation with
# @param :customer [Integer] The id of the customer of the conversation
get '/message/:id/:customer' do
  customer = User.find_by_id(params[:customer])
  listing = Listing.find_by_id(params[:id])
  raise Sinatra::NotFound unless listing && customer
  return forbidden unless listing.seller == current_user
  return forbidden if customer == current_user

  slim :'user/messages', locals: { to: customer, listing: listing, messages: Message.conversation(customer, listing) }
end

# Sends a message to the seller of an listing
# @param :id [Integer] The id of the listing to send the message to the seller of
post '/message/:id' do
  listing = Listing.find_by_id(params[:id])
  raise Sinatra::NotFound unless listing
  return forbidden unless listing.seller != current_user

  Message.create(listing, current_user, listing.seller, params[:content]) unless params[:content].empty?
  redirect "/message/#{listing.id}"
end

# Sends a message to a user as the seller of an listing
# @param :id [Integer] The id of the listing to send the message from
# @param :customer [Integer] The id of the user to send the message to
post '/message/:id/:customer' do
  customer = User.find_by_id(params[:customer])
  listing = Listing.find_by_id(params[:id])
  raise Sinatra::NotFound unless listing && customer
  return forbidden unless listing.seller == current_user
  return forbidden if customer == current_user

  Message.create(listing, current_user, customer, params[:content]) unless params[:content].empty?
  redirect "/message/#{listing.id}/#{customer.id}"
end

# Shows the base messages page, where the user can select which conversation to see
get '/messages' do
  slim :'user/messages', locals: { listing: nil }
end

# Creates a user
# @param name [String] The name of the user
# @param email [String] The email of the user
# @param password [String] The password of the user
# @param 'confirm-password' [String] The password confirmation of the user
# @param postal_code [String] The postal code of the user
#
# @see User#create
post '/register' do
  error = nil
  return too_many_requests('/register') unless Time.now.to_f - RATE_LIMITS[:register][request.ip] > 10

  postal_code = params[:postal_code].delete(' ').delete('-').to_i
  error = 'Postnummret måste vara 5 siffror' unless postal_code.to_s.length == 5
  error = 'Lösenorden matchar inte' unless params[:password] == params[:'confirm-password']
  error = 'Du måste ange ett lösenord' if params[:password] && params[:password].empty?
  error = 'Du måste ange ett namn' if params[:name] && params[:name].empty?
  error = 'Du måste ange en giltig e-postadress' unless validate_email(params[:email])
  error = 'Ditt namn måste vara kortare än 16 tecken' if (params[:name]&.length || 0) > 17
  unless params[:name].match?(/^[äÄöÖåÅa-zA-Z\-_0-9]+$/)
    error = 'Ditt namn måste bestå av endast bokstäver, bindestreck och understreck'
  end

  if error
    session[:old_data] = params
    session[:form_error] = error
    return redirect '/register'
  end
  user_id = User.create(params[:name], params[:email], params[:password], postal_code)
  if !user_id.nil?
    RATE_LIMITS[:register][request.ip] = Time.now.to_f
    session[:user_id] = user_id
    redirect(temp_session(:return_to) || '/')
  else
    session[:form_error] = 'Mailadress är redan registrerad'
    session[:old_data] = params
    redirect '/register'
  end
end

# Logs in a user
# @param email [String] The email of the user
# @param password [String] The password of the user
post '/login' do
  return too_many_requests('/login') unless Time.now.to_f - RATE_LIMITS[:login][request.ip] > 1

  user = User.find_by_email(params[:email])
  if user&.verify_password(params[:password])
    session[:user_id] = user.id
    redirect(temp_session(:return_to) || '/')
  else
    RATE_LIMITS[:login][request.ip] = Time.now.to_f
    session[:form_error] = 'Felaktig mailadress eller lösenord'
    session[:old_data] = params
    redirect '/login'
  end
end

puts "Timezone is #{Time.now.zone} with offset #{Time.now.utc_offset / 3600}h"
