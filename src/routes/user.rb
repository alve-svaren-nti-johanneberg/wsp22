# frozen_string_literal: true

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

get '/user/edit' do
  return unauthorized unless current_user

  slim :'user/edit'
end

post '/user/edit' do
  return unauthorized unless current_user

  unless current_user.verify_password(params[:password])
    session[:form_error] = 'Lösenordet stämmer inte'
    return redirect '/user/edit'
  end

  current_user.update(params[:name], params[:email], params[:postal_code], params[:new_password])
  redirect "/user/#{current_user.id}"
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

  slim :'user/messages',
       locals: { to: listing.seller, listing: listing, messages: Message.conversation(current_user, listing) }
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

get '/request-reset-password' do
  slim :'user/request-reset-password'
end

get '/reset-password' do
  user = check_valid_token(params[:token])
  return forbidden unless user

  slim :'user/reset-password', { locals: { user: user, token: params[:token] } }
end

post '/reset-password' do
  user = check_valid_token(params[:token])
  return forbidden unless user

  user.update_password(params[:password])
  session[:msg] = 'Lösenordet har ändrats'
  session[:success] = true
  redirect '/login'
end

post '/request-reset-password' do
  user = User.find_by_email(params[:email])
  session[:form_error] = 'Mailadressen kunde inte hittas' unless user
  return redirect '/request-reset-password' unless user

  send_reset_email(user)
  session[:msg] = "Ett mail har skickats till #{params[:email]}"
  session[:success] = true
  redirect '/login'
end

post '/user/:id/admin' do
  user = User.find_by_id(params[:id])
  raise Sinatra::NotFound unless user
  return forbidden unless current_user.admin

  user.admin = params[:admin].to_i == 1
  redirect "/user/#{user.id}"
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
