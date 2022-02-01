# frozen_string_literal: true

require 'sinatra'
require 'sinatra/reloader'
require 'slim'
require 'sassc'
require 'bcrypt'
require 'sqlite3'

enable :sessions

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

get '/register' do
  slim :register
end

get '/search' do
  params[:query]
  slim :search
end

post '/register' do
  # Create a new user
end

post '/login' do
  # Login a user
end
