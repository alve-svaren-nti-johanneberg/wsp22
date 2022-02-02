# frozen_string_literal: true

require 'sinatra'
require 'sinatra/reloader'
require 'slim'
require 'sassc'
require_relative 'database'
require_relative 'utils'

enable :sessions

also_reload 'database.rb', 'utils.rb'

allowed_without_login = %w[/ /login /register /style.css /favicon.ico]

before do
  if !current_user && !allowed_without_login.include?(request.path_info)
    session[:return_to] = request.path_info
    redirect '/login'
  end
  # if session[:user_id]
  #   puts "User #{current_user.email} is logged in"
  #   current_user
  # end
end

get '/' do
  slim :index
end

# Generate and serve project sass
get '/style.css' do
  scss :'scss/style', style: :compressed
end

get '/ad/new' do
  slim :'ad/create'
end

post '/ad/new' do
  if (params[:price] || '0').to_i.negative?
    session[:form_error] = 'Priset måste vara positivt'
    session[:old_data] = params
    redirect '/ad/new'
  end
  ad = Ad.create(params[:title], params[:content], params[:price], current_user.id, params[:postal_code])
  redirect "/ad/#{ad}"
end

get '/ad/:id' do
  ad = Ad.find_by_id(params[:id])
  if ad
    slim :'ad/view', locals: { ad: ad }
  else
    slim :'ad/404'
  end
end

get '/ad/:id/edit' do
  slim :'ad/update'
end

post '/ad/:id/delete' do
  ad = Ad.find_by_id(params[:id])
  if ad
    ad.delete
    session[:msg] = 'Annonsen har raderats'
    session[:success] = true
    redirect '/'
  else
    slim :'ad/404'
  end
end

get '/login' do
  slim :login
end

get '/logout' do
  session.clear
  redirect '/'
end

get '/register' do
  slim :register
end

get '/search' do
  ads = Ad.search(params[:query].split(' '))
  slim :search, locals: { ads: ads }
end

post '/register' do
  if params[:password] == params[:'confirm-password']
    user_id = User.create(params[:email], params[:password])
    session[:user_id] = user_id
    redirect '/'
  else
    session[:form_error] = 'Lösenorden matchar inte'
    redirect '/register'
  end
end

post '/login' do
  user = User.find_by_email(params[:email])
  if user&.verify_password(params[:password])
    session[:user_id] = user.id
    redirect '/'
  else
    session[:form_error] = 'Felaktigt användarnamn eller lösenord'
    redirect '/login'
  end
end
