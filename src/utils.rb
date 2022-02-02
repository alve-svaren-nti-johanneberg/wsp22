# frozen_string_literal: true

require 'sinatra'
require_relative 'database'

def temp_session(symbol)
  value = session[symbol]
  session.delete(symbol)
  value
end

def current_user
  User.find_by_id(session[:user_id])
end
