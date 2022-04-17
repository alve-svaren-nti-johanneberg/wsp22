# frozen_string_literal: true

require 'bcrypt'
require 'sqlite3'
require_relative 'utils'

def db
  tmp = SQLite3::Database.new File.join(File.dirname(__FILE__), './data.db')
  tmp.results_as_hash = true
  tmp
end

# An abstract class for all database objects
class DbModel
  # @return [Integer]
  attr_reader :id

  # @return [Hash<String, String>]
  attr_reader :hash

  def self.table_name; end

  def self.create_table; end

  def table_name
    self.class.table_name
  end

  def initialize(data)
    @hash = data
    @id = data['id']
  end

  def ==(other)
    return false if other.nil?
    return @id == other if other.is_a?(Numeric)

    @id == other.id
  end

  def self.find_by_id(id)
    data = db.execute("SELECT * FROM #{table_name} WHERE id = ?", id).first
    data && new(data)
  end
end

# A user
class User < DbModel
  attr_reader :email, :name, :admin, :created_at, :postal_code, :password_hash

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
    @admin = data['admin'] == 1
    @created_at = Time.at(data['created_at'])
    @postal_code = data['postal_code']
    @password_hash = BCrypt::Password.new(data['password_hash'])
  end

  # @param name [String]
  # @param email [String]
  # @param password [String]
  # @param postal_code [String]
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
    data && new(data)
  end

  def verify_password(password)
    @password_hash == password
  end

  def listings
    db.execute("SELECT * FROM #{Listing.table_name} WHERE seller_id = ?", @id).map do |listing|
      Listing.new(listing)
    end
  end

  def conversations
    @conversations ||= begin
      as_seller = []
      as_customer = []
      db.execute(
        "SELECT * FROM #{Message.table_name} WHERE customer_id = ? OR listing_id IN (SELECT id FROM #{Listing.table_name} WHERE seller_id = ?)", @id, @id
      ).map do |message|
        message = Message.new(message)
        unless as_seller.include?([message.listing.id, message.customer.id]) || as_customer.include?(message.listing.id)
          if message.customer == self
            as_customer << message.listing.id
          else
            as_seller << [message.listing.id, message.customer.id]
          end
        end
      end
      { seller: as_seller, customer: as_customer }
    end
  end

  def update_password(password)
    hash = BCrypt::Password.create(password)
    db.execute("UPDATE #{table_name} SET password_hash = ? WHERE id = ?", hash, @id)
  end

  # @param name [String]
  # @param email [String]
  # @param postal_code [String]
  # @param password [String, nil]
  def update(name, email, postal_code, password)
    db.execute("UPDATE #{table_name} SET
      name = ?,
      email = ?,
      postal_code = ? WHERE id = ?", name, email, postal_code, @id)
    update_password(password) if password
  end
end

# An listing that a user created
class Listing < DbModel
  attr_reader :price, :seller, :title, :content, :sold, :postal_code, :image_name, :created_at

  def self.table_name
    'Listings'
  end

  def self.create_table
    db.execute("CREATE TABLE IF NOT EXISTS `#{table_name}` (
      `id` INTEGER NOT NULL UNIQUE,
      `price` INTEGER NOT NULL,
      `title` TEXT NOT NULL,
      `content` TEXT NOT NULL,
      `sold` INTEGER NOT NULL DEFAULT 0,
      `seller_id` INTEGER NOT NULL,
      `postal_code` TEXT NOT NULL,
      `image_name` TEXT,
      `created_at` INTEGER NOT NULL,
      FOREIGN KEY(`seller_id`) REFERENCES `#{User.table_name}`(`id`),
      PRIMARY KEY(`id` AUTOINCREMENT))")
  end

  def initialize(data)
    super data
    @price = data['price']
    @seller = User.find_by_id(data['seller_id'])
    @title = data['title']
    @postal_code = data['postal_code']
    @content = data['content']
    @sold = data['sold']
    @image_name = data['image_name']
    @created_at = Time.at(data['created_at'])
  end

  # @param title [String]
  # @param content [String]
  # @param price [Integer]
  # @param seller_id [Integer]
  # @param postal_code [String, Integer]
  # @param tags [Array<Integer>]
  def self.create(title, content, price, seller_id, postal_code, image_name, tags)
    session = db
    session.execute("INSERT INTO #{table_name}
      (title, content, price, seller_id, postal_code, image_name, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    title, content, price, seller_id, postal_code, image_name, Time.now.to_i)
    listing = find_by_id(session.last_insert_row_id)
    tags.each do |tag_id|
      listing.add_tag(tag_id)
    end
    listing
  end

  # @param title [String]
  # @param content [String]
  # @param price [Integer]
  # @param seller_id [Integer]
  # @param postal_code [String, Integer]
  # @param tags [Array<Integer>]
  def update(title, content, price, seller_id, postal_code, image_name, tags)
    session = db
    session.execute("UPDATE #{table_name} SET
      title = ?,
      content = ?,
      price = ?,
      seller_id = ?,
      postal_code = ?,
      image_name = ?,
      created_at = ? WHERE id = ?", title, content, price, seller_id, postal_code, image_name, Time.now.to_i, id)

    clear_tags
    tags.each do |tag_id|
      add_tag(tag_id)
    end
  end

  # @return [Array<Listing>]
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
    db.execute("DELETE FROM #{Message.table_name} WHERE listing_id = ?", @id)
    File.delete(File.join(File.dirname(__FILE__), "userimgs/#{@image_name}")) if @image_name
  end

  def tags
    @tags ||= begin
      data = db.execute("SELECT * FROM #{ListingTag.table_name} WHERE listing_id = ?", @id)
      data.map { |tag| Tag.find_by_id(tag['tag_id']) }
    end
  end

  def add_tag(tag_id)
    db.execute("INSERT INTO #{ListingTag.table_name} (listing_id, tag_id) VALUES (?, ?)", @id, tag_id)
  end

  def clear_tags
    db.execute("DELETE FROM #{ListingTag.table_name} WHERE listing_id = ?", @id)
  end
end

# A message that someone sent
class Message < DbModel
  attr_reader :content, :listing, :customer, :sender, :receiver, :timestamp

  def self.table_name
    'Messages'
  end

  def self.create_table
    db.execute("CREATE TABLE IF NOT EXISTS `#{table_name}` (
      `id` INTEGER NOT NULL UNIQUE,
      `content` TEXT NOT NULL,
      `listing_id` INTEGER NOT NULL,
      `customer_id` INTEGER NOT NULL,
      `is_from_customer` INTEGER NOT NULL,
      `timestamp` INTEGER NOT NULL,
      FOREIGN KEY(`customer_id`) REFERENCES `#{User.table_name}`(`id`),
      FOREIGN KEY(`listing_id`) REFERENCES `#{Listing.table_name}`(`id`),
      PRIMARY KEY(`id` AUTOINCREMENT))")
  end

  # @param user [User]
  # @param listing [Listing]
  def self.conversation(user, listing)
    db.execute("SELECT * FROM #{table_name} WHERE customer_id = ? AND listing_id = ?", user.id, listing.id).map do |data|
      new(data)
    end
  end

  def initialize(data)
    super data
    @listing = Listing.find_by_id(data['listing_id'])
    @content = data['content']
    @timestamp = Time.at(data['timestamp'])
    @customer = User.find_by_id(data['customer_id'])
    @from_customer = !data['is_from_customer'].zero?
    @sender = @from_customer ? @customer : @listing.seller
    @receiver = @from_customer ? @listing.seller : @customer
  end

  # @param listing [Listing]
  # @param sender [User]
  # @param receiver [User]
  # @param content [String]
  def self.create(listing, sender, receiver, content)
    from_customer = sender != listing.seller
    session = db
    session.execute(
      "INSERT INTO #{table_name} (listing_id, customer_id, is_from_customer, content, timestamp) VALUES (?, ?, ?, ?, ?)",
      listing.id, (from_customer ? sender : receiver).id, from_customer ? 1 : 0, content, Time.now.to_i
    )
    session.last_insert_row_id
  end
end

# The association table for tags on listing
class ListingTag < DbModel
  attr_reader :tag_id, :ad_id

  def self.table_name
    Listing.table_name + Tag.table_name
  end

  def self.create_table
    db.execute("CREATE TABLE IF NOT EXISTS `#{table_name}` (
      `id` INTEGER NOT NULL UNIQUE,
      `tag_id` INTEGER NOT NULL,
      `listing_id` INTEGER NOT NULL,
      FOREIGN KEY(`tag_id`) REFERENCES `#{Tag.table_name}`(`id`),
      FOREIGN KEY(`listing_id`) REFERENCES `#{Listing.table_name}`(`id`),
      PRIMARY KEY(`id` AUTOINCREMENT))")
  end

  def initialize(data)
    super data
    @tag_id = data['tag_id']
    @ad_id = data['listing_id']
  end
end

# A tag
class Tag < DbModel
  attr_reader :name, :slug

  def self.table_name
    'Tags'
  end

  def self.create_table
    db.execute("CREATE TABLE IF NOT EXISTS `#{table_name}` (
      `id` INTEGER NOT NULL UNIQUE,
      `name` TEXT NOT NULL,
      `slug` TEXT NOT NULL UNIQUE,
      PRIMARY KEY(`id` AUTOINCREMENT))")
  end

  def initialize(data)
    super data
    @name = data['name']
    @slug = data['slug']
  end

  def self.find_by_slug(slug)
    return nil if slug.empty?

    data = db.execute("SELECT * FROM #{table_name} WHERE slug = ?", slug).first
    data && new(data)
  end

  def self.all
    data = db.execute("SELECT * FROM #{table_name}")
    data.map { |tag| new(tag) }
  end

  def listings
    @listings ||= begin
      data = db.execute("SELECT * FROM #{ListingTag.table_name} WHERE tag_id = ?", @id)
      data.map { |listings| Listing.find_by_id(listings['listing_id']) }
    end
  end

  def self.create(name)
    slug = name.downcase.gsub(/[^a-z0-9]+/, '-')
    return nil if find_by_slug(slug)

    session = db
    session.execute("INSERT INTO #{table_name} (name, slug) VALUES (?, ?)", name, slug)
    session.last_insert_row_id
  end
end

Dir.mkdir('userimgs') unless Dir.exist?('userimgs')

User.create_table
Listing.create_table
Message.create_table
Tag.create_table
ListingTag.create_table
