# frozen_string_literal: true

require 'sinatra'
require 'slim'
require 'sassc'
require 'securerandom'
require 'rmagick'
require_relative 'models'
require_relative 'utils'
require_relative 'routes'

include Utils

if settings.development?
  require 'rack-livereload'
  require 'sinatra/reloader'

  # use Rack::LiveReload, source: :vendored

  # @guard ||= Thread.new do
  #   system('bundle exec guard')
  # end

  also_reload 'models.rb', 'utils.rb', 'routes.rb', 'routes/user.rb'
end

enable :sessions

puts "Timezone is #{Time.now.zone} with offset #{Time.now.utc_offset / 3600}h"
