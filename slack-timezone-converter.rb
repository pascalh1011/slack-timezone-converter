require 'rubygems'
require 'bundler/setup'
require 'active_support/all'
require 'json'
Bundler.require

TOKEN = ARGV[0]         # Get one at https://api.slack.com/web#basics
PER_LINE = ARGV[1] || 1 # Number of times per line
MESSAGE = ARGV[2].to_s  # Additional message to be appended

# Get a Slack clock emoji from a time object

def slack_clock_emoji_from_time(time)
  hour = time.hour % 12
  hour = 12 if hour == 0
  ":clock#{hour}:"
end

# Get the current user from token

uri = URI.parse("https://slack.com/api/auth.test?token=#{TOKEN}")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.verify_mode = OpenSSL::SSL::VERIFY_NONE
response = http.get(uri.request_uri)
CURRENT_USER = JSON.parse(response.body)['user_id']

# Get users list and all available timezones and set default timezone

uri = URI.parse("https://slack.com/api/users.list?token=#{TOKEN}")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.verify_mode = OpenSSL::SSL::VERIFY_NONE
response = http.get(uri.request_uri)
timezones = {}
users = {}
timezones_by_user_id = {}
maxlen = 0

JSON.parse(response.body)['members'].each do |user|
  offset, label = user['tz_offset'], user['tz_label']
  next if offset.nil? or offset == 0 or label.nil?
  timezones[label] = offset / 3600 unless timezones.has_key?(label)
  timezones_by_user_id[user['id']] = offset
  users[label] ||= Array.new
  users[label] << user['name']
  user_label = users[label].join(', ')
  maxlen = user_label.length if user_label.length > maxlen
  DEFAULT_TIMEZONE = ActiveSupport::TimeZone[timezones[label]].tzinfo.name if user['id'] == CURRENT_USER
end


#Time.zone = DEFAULT_TIMEZONE

# Connect to Slack

url = SlackRTM.get_url token: TOKEN 
client = SlackRTM::Client.new websocket_url: url

# Listen for new messages (events of type "message")

puts "[#{Time.now}] Connected to Slack!"

client.on :message do |data|
  if data['type'] === 'message' and !data['text'].nil? and data['subtype'].nil? and data['reply_to'].nil? and
     !data['text'].gsub(/<[^>]+>/, '').match(/[0-9](([hH]([0123456789 ?:,;.]|$))|( ?[aA][mM])|( ?[pP][mM])|(:[0-9]{2}))/).nil?
    
    # Identify time patterns
      text = data['text']
      Time.zone = ActiveSupport::TimeZone[timezones_by_user_id[data['user']]]
      time = Time.zone.parse(text).utc 
      puts "[#{Time.now}] Got time #{time} #{data.inspect}"

      text = ["*#{time.strftime('%I:%M %p')}* in UTC is:\n\n"]

      uri = URI.parse("https://slack.com/api/channels.info?token=#{TOKEN}&channel=#{data['channel']}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      response = http.get(uri.request_uri)

      user_ids = JSON.parse(response.body)['channel']['members']

      i = 0
      timezones.each do |time_zone, offset|
        next unless timezones_by_user_id.select { |k,v| user_ids.include?(k) && offset.to_i.hours == v }.any?
        i += 1
        label = users[time_zone].join(', ')
        localtime = time + offset.to_i.hours
        emoji = slack_clock_emoji_from_time(localtime)
        space = " " * (maxlen - label.length)
        space = " "
        message = "#{emoji} *#{localtime.strftime('%I:%M %p')}*: #{label}#{space}"
        message += (i % PER_LINE.to_i == 0) ? "\n" : " "
        text << message
      end

      text << (MESSAGE % time.to_i.to_s)

      puts "[#{Time.now}] Sending message..."
      client.send({ type: 'message', channel: data['channel'], text: text.join })
    
      # Just ignore the message
    
  end
end

# Runs forever until an exception happens or the process is stopped/killed

client.main_loop
assert false
