# frozen_string_literal: true

require 'sinatra'
require 'sinatra/reloader'
require 'slim'
require 'sassc'
require 'securerandom'
require 'rmagick'
require 'rack-livereload'
require_relative 'models'
require_relative 'utils'

use Rack::LiveReload, source: :vendored

Thread.new do
  system('bundle exec guard')
end

enable :sessions

also_reload 'models.rb', 'utils.rb'

auth_needed = %w[/ad/new /message]
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

not_found do
  slim :'generic/404'
end

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

get '/auth-needed' do
  unauthorized
end

# Generate and serve project sass
get '/style.css' do
  scss :'scss/style', style: :compressed
end

get '/ad/new' do
  slim :'ad/edit_or_create'
end

post '/ad/new' do
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
    return redirect '/ad/new'
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

  ad = Ad.create(
    params[:title], params[:content], params[:price].to_i,
    current_user.id, postal_code, new_name, params[:categories] || []
  )
  redirect "/ad/#{ad.id}"
end

get '/ad/:id/edit' do
  ad = Ad.find_by_id(params[:id])
  slim :'ad/edit_or_create', locals: { ad: ad }
end

post '/ad/:id/update' do
  ad = Ad.find_by_id(params[:id])

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
    return redirect '/ad/new'
  end

  new_name = nil

  if params[:cover]
    File.delete("userimgs/#{ad.image_name}") if ad.image_name
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

  ad.update(
    params[:title], params[:content], params[:price].to_i,
    current_user.id, postal_code, new_name || ad.image_name, params[:categories]
  )

  redirect "/ad/#{ad.id}"
end

get '/categories' do
  slim :'ad/categories'
end

post '/categories' do
  return unauthorized unless current_user.admin

  session[:form_error] = "Kategorin '#{params[:name]}' finns redan" unless Category.create(params[:name])
  redirect '/categories'
end

get '/ad/:id' do
  ad = Ad.find_by_id(params[:id])
  raise Sinatra::NotFound unless ad

  slim :'ad/view', locals: { ad: ad }
end

get '/userimg/:filename' do
  send_file File.join(File.dirname(__FILE__), "userimgs/#{params[:filename]}")
end

get '/ad/:id/edit' do
  slim :'ad/update'
end

post '/ad/:id/delete' do
  ad = Ad.find_by_id(params[:id])
  raise Sinatra::NotFound unless ad

  return forbidden unless ad.seller == current_user || current_user.admin

  ad.delete
  session[:msg] = 'Annonsen har raderats'
  session[:success] = true
  redirect '/'
end

get '/login' do
  slim :'user/login'
end

get '/logout' do
  session.clear
  redirect '/'
end

get '/register' do
  slim :'user/register'
end

get '/search' do
  ads = Ad.search((params[:query] || '').split(' '))
  p params
  ads.keep_if do |ad|
    filters = []
    filters << (ad.price <= params[:max_price].to_i if params[:max_price] && !params[:max_price].empty?)
    filters << (ad.price >= params[:min_price].to_i if params[:min_price] && !params[:min_price].empty?)
    filters << (((params[:categories].all? { |category_id| ad.categories.include?(category_id.to_i) }) if params[:categories]))
    filters << ((postal_code_distance(ad.postal_code, current_user.postal_code) || 0) <= params[:max_distance].to_i if params[:max_distance] && !params[:max_distance].to_i == 100)
    filters.reject!(&:nil?)
    p filters
    filters.all?
  end
  slim :'ad/search', locals: { ads: ads }
end

get '/user/:id' do
  user = User.find_by_id(params[:id])
  raise Sinatra::NotFound unless user

  slim :'user/profile', locals: { user: user }
end

get '/message/:id' do
  ad = Ad.find_by_id(params[:id])
  raise Sinatra::NotFound unless ad
  return forbidden unless ad.seller != current_user

  slim :'user/messages', locals: { to: ad.seller, ad: ad, messages: Message.conversation(current_user, ad) }
end

post '/message/:id' do
  ad = Ad.find_by_id(params[:id])
  raise Sinatra::NotFound unless ad
  return forbidden unless ad.seller != current_user

  Message.create(ad, current_user, ad.seller, params[:content]) unless params[:content].empty?
  redirect "/message/#{ad.id}"
end

post '/message/:id/:customer' do
  customer = User.find_by_id(params[:customer])
  ad = Ad.find_by_id(params[:id])
  raise Sinatra::NotFound unless ad && customer
  return forbidden unless ad.seller == current_user
  return forbidden if customer == current_user

  Message.create(ad, current_user, customer, params[:content]) unless params[:content].empty?
  redirect "/message/#{ad.id}/#{customer.id}"
end

get '/message/:id/:customer' do
  customer = User.find_by_id(params[:customer])
  ad = Ad.find_by_id(params[:id])
  raise Sinatra::NotFound unless ad && customer
  return forbidden unless ad.seller == current_user
  return forbidden if customer == current_user

  slim :'user/messages', locals: { to: customer, ad: ad, messages: Message.conversation(customer, ad) }
end

get '/messages' do
  slim :'user/messages', locals: { ad: nil }
end

post '/register' do
  error = nil

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
    session[:user_id] = user_id
    redirect(temp_session(:return_to) || '/')
  else
    session[:form_error] = 'Mailadress är redan registrerad'
    session[:old_data] = params
    redirect '/register'
  end
end

post '/login' do
  user = User.find_by_email(params[:email])
  if user&.verify_password(params[:password])
    session[:user_id] = user.id
    redirect(temp_session(:return_to) || '/')
  else
    session[:form_error] = 'Felaktig mailadress eller lösenord'
    session[:old_data] = params
    redirect '/login'
  end
end

puts "Timezone is #{Time.now.zone} with offset #{Time.now.utc_offset / 3600}h"
