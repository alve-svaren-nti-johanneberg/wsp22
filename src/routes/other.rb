# frozen_string_literal: true

auth_needed = %w[/listing/new /message /user/edit]
ignored_paths = %w[/style.css /favicon.ico /auth-needed]
auth_paths = %w[/login /register /auth-needed]

RATE_LIMITS ||= Hash.new(Hash.new(0))

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

# Fetches an image for an listing
# @param :filename [String] The filename for the processed listing image
get '/userimg/:filename' do
  send_file File.join(File.dirname(__FILE__), "../userimgs/#{params[:filename]}")
end
