# frozen_string_literal: true

require 'sinatra'
require 'csv'
require_relative 'database'

def temp_session(symbol)
  value = session[symbol]
  session.delete(symbol)
  value
end

# @return [User]
def current_user
  User.find_by_id(session[:user_id])
end

def validate_email(email)
  (/\A[a-z0-9+-_.]+@[a-z\d\-.]+\.[a-z]+\z/i).match?(email)
end

def group_number(num, length = 3)
  # 12345 => 12 345
  format('%i', num).chars.reverse.each_slice(length).reverse_each.map { |x| x.reverse.join }.join(' ')
end

def get_human_readable_price(price)
  price.positive? ? "#{group_number(price, 3)} kr" : 'Gratis'
end

def get_banner_date(time)
  months = %w[Januari Februari Mars April Maj Juni Juli Augusti September Oktober November December]
  days = %w[Söndag Måndag Tisdag Onsdag Torsdag Fredag Lördag]

  time.strftime("#{days[time.wday]} %-d #{months[time.month - 1]} %Y")
end

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

def get_distance(lat1, lon1, lat2, lon2)
  rad_per_deg = Math::PI / 180

  earth_radius = 6371

  part1 = Math.sin(((lat2 - lat1) * rad_per_deg) / 2)**2
  part2 = Math.sin(((lon2 - lon1) * rad_per_deg) / 2)**2 * Math.cos(lat1 * rad_per_deg) * Math.cos(lat2 * rad_per_deg)

  haversine = part1 + part2

  c = 2 * Math.asin(Math.sqrt(haversine))

  earth_radius * c * 1000
end

def postal_code_distance(code1, code2)
  code1_data = postal_codes[code1]
  code2_data = postal_codes[code2]
  return nil unless code1_data && code2_data
  lat1, lon1 = *code1_data['coords']
  lat2, lon2 = *code2_data['coords']

  get_distance(lat1, lon1, lat2, lon2)
end

def human_readable_distance(ad)
  distance = postal_code_distance(current_user.postal_code, ad.postal_code) / 1000
  text = "#{group_number(distance.to_i)} km"
  text = 'Inom 2 km' if distance < 2

  text
end

def ad_position(ad)
  place = postal_codes[ad.postal_code]
  return "Okänd plats (#{ad.postal_code})" unless place

  text = "#{place['place_name']}, #{place['admin_name1']}"
  text = place['place_name'] if place['admin_name1'] == place['place_name']
  return "#{text} · #{human_readable_distance(ad)}" if current_user

  text
end
