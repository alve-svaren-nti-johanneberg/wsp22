# frozen_string_literal: true

require 'sinatra'
require 'sinatra/reloader'
require 'slim'
require 'sassc'
require_relative 'database'
require_relative 'utils'

enable :sessions

also_reload 'database.rb', 'utils.rb'

before do
  if session[:user_id]
    puts "User #{current_user.email} is logged in"
    current_user
  end
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

get '/ad/:id' do
  slim :'ad/view'
end

get '/ad/:id/edit' do
  slim :'ad/update'
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
  params[:query]
  slim :search
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
