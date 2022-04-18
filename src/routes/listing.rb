# frozen_string_literal: true

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
                   (params[:tags].all? do |tag_slug|
                      listing.tags.map(&:slug).include?(tag_slug)
                    end)
                 end))
    if params[:max_distance] && params[:max_distance].to_i != 100
      filters << ((postal_code_distance(listing.postal_code,
                                        current_user.postal_code) || 100) <= params[:max_distance].to_i)
    end
    filters.reject!(&:nil?)
    filters.all?
  end
  slim :'listing/search', locals: { listings: listings }
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
