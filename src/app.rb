# frozen_string_literal: true

require 'sinatra'
require 'sinatra/reloader'
require 'slim'
require 'sassc'
require_relative 'database'
require_relative 'utils'

enable :sessions

also_reload 'database.rb', 'utils.rb'

auth_needed = %w[/ad/new]
ignored_paths = %w[/style.css /favicon.ico]

before do
  return if ignored_paths.include? request.path_info

  if !current_user && auth_needed.map { |path| request.path_info.start_with?(path) }.any?
    session[:return_to] = request.fullpath
    redirect '/login'
  end
  # If the user has gone and done something else than logging in or registering,
  # make sure to not return back after logging/registering in later
  !(request.path_info == '/login' || request.path_info == '/register') && session.delete(:return_to)
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
  error = nil

  postal_code = params[:postal_code].delete(' ').delete('-').to_i
  error = 'Postnummret måste vara 5 siffror' unless postal_code.to_s.length == 5
  error = 'Priset måste vara positivt' if params[:price].to_i.negative?
  error = 'Du måste ange ett postnummer' if params[:postal_code].empty?
  error = 'Du måste ange en beskrivning' if params[:content].empty?
  error = 'Du måste ange en titel' if params[:title].empty?

  if error
    session[:old_data] = params
    session[:form_error] = error
    return redirect '/ad/new'
  end

  ad = Ad.create(params[:title], params[:content], params[:price].to_i, current_user.id, postal_code)
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
  ads = Ad.search((params[:query] || '').split(' '))
  slim :search, locals: { ads: ads }
end

post '/register' do
  error = nil

  error = 'Lösenorden matchar inte' unless params[:password] == params[:'confirm-password']
  error = 'Du måste ange ett lösenord' if params[:password].empty?
  error = 'Du måste ange ett namn' if params[:name].empty?
  error = 'Du måste ange en giltig e-postadress' unless validate_email(params[:email])
  error = 'Ditt namn måste vara kortare än 16 tecken' if params[:name].length > 16
  unless params[:name].match?(/^[a-zA-Z\-_]+$/)
    error = 'Ditt namn måste bestå av endast bokstäver, bindestreck och understreck'
  end

  if error
    session[:old_data] = params
    session[:form_error] = error
    return redirect '/register'
  end

  user_id = User.create(params[:name], params[:email], params[:password])
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
