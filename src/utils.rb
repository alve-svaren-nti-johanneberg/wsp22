# frozen_string_literal: true

require 'sinatra'
require 'csv'
require 'mailgun-ruby'
require 'slim'
require 'jwt'
require 'digest'
require 'securerandom'
require_relative 'models'

# Module for utility functions
module Utils
  def jwt_secret
    warn 'JWT_SECRET is not set, using fallback secret' unless ENV['JWT_SECRET']
    @jwt_secret ||= ENV['JWT_SECRET'] || 'fallbacksecret'
  end

  def temp_session(symbol)
    value = session[symbol]
    session.delete(symbol)
    value
  end

  # Gets the current user from the session, if any
  # @return [User]
  # @return [nil] if no user is logged in
  def current_user
    User.find_by_id(session[:user_id])
  end

  # Validates an email address
  # @param email [String]
  # @return [Boolean]
  def validate_email(email)
    (/\A[a-z0-9+-_.]+@[a-z\d\-.]+\.[a-z]+\z/i).match?(email)
  end

  # Returns a string with the given number grouped by 3, or the specified length
  # @param number [Integer]
  # @param length [Integer] The length of each group, defaults to 3
  # @return [String]
  def group_number(num, length = 3)
    # 12345 => 12 345
    format('%i', num).chars.reverse.each_slice(length).reverse_each.map { |x| x.reverse.join }.join(' ')
  end

  # Returns a human readable version of a price
  # @param price [Integer]
  # @return [String]
  def get_human_readable_price(price)
    price.positive? ? "#{group_number(price, 3)} kr" : 'Gratis'
  end

  # Returns a human readable banner date to show in messages
  # @param time [Date]
  # @return [String]
  def get_banner_date(time)
    months = %w[Januari Februari Mars April Maj Juni Juli Augusti September Oktober November December]
    days = %w[Söndag Måndag Tisdag Onsdag Torsdag Fredag Lördag]

    time.strftime("#{days[time.wday]} %-d #{months[time.month - 1]} %Y")
  end

  # Get the postal codes from the CSV file and generate a hash from the data
  # Note: This function is memoized
  # @return [Hash<String, Hash>]
  def postal_codes
    @postal_codes ||= begin
      codes = {}
      csv_codes = CSV.read(File.join(File.dirname(__FILE__), './postal_codes.csv'), headers: true)
      csv_codes.each do |row|
        codes[row['postal_code']] = row.to_h
        current = codes[row['postal_code']]
        current['coords'] = [current['latitude'].to_f, current['longitude'].to_f]
      end
      codes
    end
  end

  # Returns the distance between two points in meters
  # @param lat1 [Float]
  # @param lon1 [Float]
  # @param lat2 [Float]
  # @param lon2 [Float]
  # @return [Float]
  def get_distance(lat1, lon1, lat2, lon2)
    rad_per_deg = Math::PI / 180

    earth_radius = 6371

    part1 = Math.sin(((lat2 - lat1) * rad_per_deg) / 2)**2
    part2 = Math.sin(((lon2 - lon1) * rad_per_deg) / 2)**2 * Math.cos(lat1 * rad_per_deg) * Math.cos(lat2 * rad_per_deg)

    haversine = part1 + part2

    c = 2 * Math.asin(Math.sqrt(haversine))

    earth_radius * c * 1000
  end

  # Returns the distance between two postal codes in meters
  # @param code1 [String]
  # @param code2 [String]
  # @return [Integer]
  def postal_code_distance(code1, code2)
    code1_data = postal_codes[code1]
    code2_data = postal_codes[code2]
    return nil unless code1_data && code2_data

    lat1, lon1 = *code1_data['coords']
    lat2, lon2 = *code2_data['coords']

    get_distance(lat1, lon1, lat2, lon2)
  end

  # Returns a human readable distance from the current user to a specified ad
  # @param listing [Listing]
  # @return [String]
  def human_readable_distance(listing)
    distance = postal_code_distance(current_user.postal_code, listing.postal_code) / 1000
    text = "#{group_number(distance.to_i)} km"
    text = 'Inom 2 km' if distance < 2

    text
  end

  # Returns the name of the place where an listing is located
  # @param listing [Listing]
  # @return [String]
  def listing_position(listing)
    place = postal_codes[listing.postal_code]
    return "Okänd plats (#{listing.postal_code})" unless place

    text = "#{place['place_name']}, #{place['admin_name1']}"
    text = place['place_name'] if place['admin_name1'] == place['place_name']
    return "#{text} · #{human_readable_distance(listing)}" if current_user

    text
  end

  def get_short_hash(data)
    Digest::SHA2.new(256).hexdigest(data)[0, 16]
  end

  # @param user [User]
  def send_reset_email(user)
    raise 'No mailgun key set' unless ENV['MAILGUN_KEY']

    token = JWT.encode(
      { iat: Time.now.to_i, sub: user.id,
        sum: get_short_hash(user.password_hash) },
      jwt_secret, 'HS256'
    )
    url = "#{request.base_url}/reset-password?token=#{token}"

    client = Mailgun::Client.new(ENV['MAILGUN_KEY'], 'api.eu.mailgun.net')
    mail = Mailgun::MessageBuilder.new
    mail.from('noreply@blocketklon.svaren.dev', { 'first' => 'Blocketklon' })
    mail.add_recipient(:to, user.email)
    mail.subject('Ändra lösenord för blocketklon')
    mail.body_html(slim(:'mail/reset-password', locals: { url: url, user: user }, layout: false))

    # Send your message through the client
    client.send_message 'blocketklon.svaren.dev', mail
  end

  # @param token [String]
  # @return [User, nil]
  def check_valid_token(token)
    p jwt_secret
    payload = nil
    return nil unless token

    begin
      payload = JWT.decode(token, jwt_secret, true, { algorithm: 'HS256' })[0]
    rescue JWT::DecodeError
      return nil
    end

    user = User.find_by_id(payload['sub'])
    return nil unless user
    return nil unless payload['sum'] == get_short_hash(user.password_hash)
    return nil unless payload['iat'] < Time.now.to_i + (24 * 3600)

    user
  end
end
