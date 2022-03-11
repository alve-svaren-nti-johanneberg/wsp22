# frozen_string_literal: true

require 'bcrypt'
require 'sqlite3'
require_relative 'utils'

def db
  tmp = SQLite3::Database.new 'data.db'
  tmp.results_as_hash = true
  tmp
end

# An abstract class for all database objects
class DbModel
  attr_reader :id

  def self.table_name; end

  def self.create_table; end

  def table_name
    self.class.table_name
  end

  def initialize(data)
    @id = data['id']
  end

  def ==(other)
    return false if other.nil?

    @id == other.id
  end

  def self.find_by_id(id)
    data = db.execute("SELECT * FROM #{table_name} WHERE id = ?", id).first
    data && new(data)
  end
end

# A user
class User < DbModel
  attr_reader :email, :name, :admin, :created_at, :postal_code

  def self.table_name
    'Users'
  end

  def self.create_table
    db.execute("CREATE TABLE IF NOT EXISTS `#{table_name}` (
      `id` INTEGER NOT NULL UNIQUE,
      `name` TEXT NOT NULL,
      `email` TEXT NOT NULL UNIQUE,
      `password_hash`	BLOB NOT NULL,
      `admin` BOOL,
      `created_at` INTEGER NOT NULL,
      `postal_code` TEXT NOT NULL,
      PRIMARY KEY(`id` AUTOINCREMENT))")
  end

  def initialize(data)
    super data
    @email = data['email']
    @name = data['name']
    @admin = data['admin'] || false
    @created_at = Time.at(data['created_at'])
    @postal_code = data['postal_code']
    @password_hash = BCrypt::Password.new(data['password_hash'])
  end

  def self.create(name, email, password, postal_code)
    hash = BCrypt::Password.create(password)
    session = db
    return nil unless session.execute("SELECT * FROM #{table_name} WHERE email = ?", email).empty?

    session.execute("INSERT INTO #{table_name}
      (name, email, password_hash, created_at, postal_code) VALUES (?, ?, ?, ?, ?)", name, email, hash, Time.now.to_i, postal_code)
    new_id = session.last_insert_row_id
    session.execute("UPDATE #{table_name} SET admin = 1 WHERE id = ?", new_id) if new_id == 1

    new_id
  end

  def self.find_by_email(email)
    return nil if email.empty?

    data = db.execute("SELECT * FROM #{table_name} WHERE email = ?", email).first
    data && User.new(data)
  end

  def verify_password(password)
    @password_hash == password
  end

  def ads
    db.execute("SELECT * FROM #{Ad.table_name} WHERE seller = ?", @id).map do |ad|
      Ad.new(ad)
    end
  end

  def conversations
    as_seller = []
    as_customer = []
    db.execute(
      "SELECT * FROM #{Message.table_name} WHERE customer = ? OR ad IN (SELECT id FROM #{Ad.table_name} WHERE seller = ?)", @id, @id
    ).map do |message|
      message = Message.new(message)
      unless as_seller.include?([message.ad.id, message.customer.id]) || as_customer.include?(message.ad.id)
        if message.customer == self
          as_customer << message.ad.id
        else
          as_seller << [message.ad.id, message.customer.id]
        end
      end
    end
    { seller: as_seller, customer: as_customer }
  end
end

# An ad that a user created
class Ad < DbModel
  attr_reader :price, :seller, :title, :content, :sold, :postal_code, :image_name

  def self.table_name
    'Ads'
  end

  def self.create_table
    db.execute("CREATE TABLE IF NOT EXISTS `#{table_name}` (
      `id` INTEGER NOT NULL UNIQUE,
      `price` INTEGER NOT NULL,
      `title` TEXT NOT NULL,
      `content` TEXT NOT NULL,
      `sold` INTEGER NOT NULL DEFAULT 0,
      `seller` INTEGER NOT NULL,
      `postal_code` TEXT NOT NULL,
      `image_name` TEXT,
      FOREIGN KEY(`seller`) REFERENCES `#{User.table_name}`(`id`),
      PRIMARY KEY(`id` AUTOINCREMENT))")
  end

  def initialize(data)
    super data
    @price = data['price']
    @seller = User.find_by_id(data['seller'])
    @title = data['title']
    @postal_code = data['postal_code']
    @content = data['content']
    @sold = data['sold']
    @image_name = data['image_name']
  end

  # @param title [String]
  # @param content [String]
  # @param price [Integer]
  # @param seller_id [Integer]
  # @param postal_code [String, Integer]
  def self.create(title, content, price, seller_id, postal_code, image_name)
    session = db
    session.execute("INSERT INTO #{table_name} (title, content, price, seller, postal_code, image_name) VALUES (?, ?, ?, ?, ?, ?)",
                    title, content, price, seller_id, postal_code, image_name)
    session.last_insert_row_id
  end

  def self.search(words)
    query = words.empty? && "SELECT * FROM #{table_name}"
    wildcards = words.map do
      'title LIKE ?'
    end
    words.map! do |word|
      "%#{word}%"
    end
    db.execute(query || "SELECT * FROM #{table_name} WHERE #{wildcards.join(' AND ')}", words).map do |data|
      new(data)
    end
  end

  def delete
    db.execute("DELETE FROM #{table_name} WHERE id = ?", @id)
    File.delete("userimgs/#{@image_name}") if @image_name
  end

  def categories
    data = db.execute("SELECT * FROM #{AdCategory.table_name} WHERE ad_id = ?", @id)
    data.length.positive? && data.map { |category| Category.find_by_id(category['category_id']) }
  end
end

# A message that someone sent
class Message < DbModel
  attr_reader :content, :ad, :customer, :sender, :receiver, :timestamp

  def self.table_name
    'Messages'
  end

  def self.create_table
    db.execute("CREATE TABLE IF NOT EXISTS `#{table_name}` (
      `id` INTEGER NOT NULL UNIQUE,
      `content` TEXT NOT NULL,
      `ad` INTEGER NOT NULL,
      `customer` INTEGER NOT NULL,
      `is_from_customer` INTEGER NOT NULL,
      `timestamp` INTEGER NOT NULL,
      FOREIGN KEY(`customer`) REFERENCES `#{User.table_name}`(`id`),
      FOREIGN KEY(`ad`) REFERENCES `#{Ad.table_name}`(`id`),
      PRIMARY KEY(`id` AUTOINCREMENT))")
  end

  # @param user [User]
  # @param ad [Ad]
  def self.conversation(user, ad)
    db.execute("SELECT * FROM #{table_name} WHERE customer = ? AND ad = ?", user.id, ad.id).map do |data|
      Message.new(data)
    end
  end

  def initialize(data)
    super data
    @ad = Ad.find_by_id(data['ad'])
    @content = data['content']
    @timestamp = Time.at(data['timestamp'])
    @customer = User.find_by_id(data['customer'])
    @from_customer = !data['is_from_customer'].zero?
    @sender = @from_customer ? @customer : @ad.seller
    @receiver = @from_customer ? @ad.seller : @customer
  end

  # @param ad [Ad]
  # @param sender [User]
  # @param receiver [User]
  # @param content [String]
  def self.create(ad, sender, receiver, content)
    from_customer = sender != ad.seller
    session = db
    session.execute(
      "INSERT INTO #{table_name} (ad, customer, is_from_customer, content, timestamp) VALUES (?, ?, ?, ?, ?)",
      ad.id, (from_customer ? sender : receiver).id, from_customer ? 1 : 0, content, Time.now.to_i
    )
    session.last_insert_row_id
  end
end

# The association table for categories on ads
class AdCategory < DbModel
  attr_reader :category_id, :ad_id

  def self.table_name
    Ad.table_name + Category.table_name
  end

  def self.create_table
    db.execute("CREATE TABLE IF NOT EXISTS `#{table_name}` (
      `id` INTEGER NOT NULL UNIQUE,
      `category_id` INTEGER NOT NULL,
      `ad_id` INTEGER NOT NULL,
      FOREIGN KEY(`category_id`) REFERENCES `#{Category.table_name}`(`id`),
      FOREIGN KEY(`ad_id`) REFERENCES `#{Ad.table_name}`(`id`),
      PRIMARY KEY(`id` AUTOINCREMENT))")
  end

  def initialize(data)
    super data
    @category_id = data['category_id']
    @ad_id = data['ad_id']
  end
end

# A category
class Category < DbModel
  attr_reader :name, :slug

  def self.table_name
    'Categories'
  end

  def self.create_table
    db.execute("CREATE TABLE IF NOT EXISTS `#{table_name}` (
      `id` INTEGER NOT NULL UNIQUE,
      `name` TEXT NOT NULL,
      `slug` TEXT NOT NULL UNIQUE,
      PRIMARY KEY(`id` AUTOINCREMENT))")
  end

  def self.find_by_slug(slug)
    return nil if slug.empty?

    data = db.execute("SELECT * FROM #{table_name} WHERE slug = ?", slug).first
    data && User.new(data)
  end

  def self.all
    data = db.execute("SELECT * FROM #{table_name}")
    data.length.positive? && data.map { |category| new(category) }
  end

  def ads
    data = db.execute("SELECT * FROM #{AdCategory.table_name} WHERE category_id = ?", @id)
    data.length.positive? && data.map { |ad| Ad.find_by_id(ad['ad_id']) }
  end

  def self.create(name)
    slug = name.downcase.gsub(/[^a-z0-9]+/, '-')
    session = db
    session.execute("INSERT INTO #{table_name} (name, slug) VALUES (?)", name, slug)
    session.last_insert_row_id
  end
end

Dir.mkdir('userimgs') unless Dir.exist?('userimgs')

User.create_table
Ad.create_table
Message.create_table
Category.create_table
AdCategory.create_table
