# frozen_string_literal: true

require 'sinatra'
require 'slim'
require 'sassc'
require 'securerandom'
require 'rmagick'
require 'sinatra/reloader'
require_relative 'models'
require_relative 'utils'
require_relative 'routes'

include Utils

also_reload('src/models.rb', 'src/utils.rb', 'src/routes.rb', *Dir.glob('src/routes/*.rb'))

# configure :development do
#   # require 'rack-livereload'

#   # use Rack::LiveReload, source: :vendored

#   # @guard ||= Thread.new do
#   #   system('bundle exec guard')
#   # end
# end

enable :sessions

puts "Timezone is #{Time.now.zone} with offset #{Time.now.utc_offset / 3600}h"
