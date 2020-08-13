require 'highline/import'
require 'yaml'
require 'net/http'
require 'json'

usage 'sync'
aliases :s
summary 'Sync events with DSA'
description 'Sync future events with the DSA panel.'
option :k, :key, 'API key for DSA', argument: :required

def bold_say(str)
  say "<%= color %(#{str}), :bold %>"
end

def bold_ask(str, *args)
  res = ask "<%= color %(#{str}), :bold %>", *args
  puts
  res
end

DSA_API = "https://localhost:8080/api/activiteiten"

# Inspired by https://github.com/nanoc/nanoc/blob/main/nanoc-cli/lib/nanoc/cli/commands/shell.rb
class SyncRunner < Nanoc::CLI::Commands::Shell

  def run
    @site = load_site
    Nanoc::Core::Compiler.new_for(@site).run_until_preprocessed
    items = env[:items]
    # Add about ~50 hours
    cut_off = DateTime.now + Rational('2.08333')
    local_events = filter_items(items, cut_off)

    api_key = "Zrl0JRxxKJHelIn5IRubA-GZiPw"

    puts "Found #{local_events.length} local events"

    # Construct a connection to the server, which will be kept open.
    uri = URI(DSA_API)
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_NONE) do |http|

      # Get remote events from DSA.
      remote_events = get_server_events(http, api_key, cut_off)["page"]["entries"]
                          .find_all { |e| e["advertise"] }
                          .find_all { |e| e["sync_data"] }
      
      puts "Found #{local_events.length} remote events"

      do_sync(http, local_events, remote_events, api_key)
    end
  end

  private

  def do_sync(http, local_events, remote_events, api_key)
    # Contains local events we want to add.
    to_add = []
    # Contains events we want to potentially update.
    to_update = []

    # Calculate the identifier for each local event.
    # We use the map (academic year) + file name without extension.
    # This is necessarily unique.
    local_events.each { |local_event|
      path = Pathname(local_event[:filename])
      academic_year = path.dirname.basename
      filename = path.basename(".*")
      identifier = "#{academic_year}-#{filename}"

      # Check if we have a remote event with the same identifier
      remote = remote_events.find { |e| e["sync_data"] == identifier }

      if remote == nil
        to_add.append([identifier, local_event])
      else
        to_update.append([identifier, remote, local_event])
      end

      remote_events.delete(remote)
    }

    puts "#{to_update.length} existing events will be updated"
    puts "#{to_add.length} new events will be added to remote"
    puts "#{remote_events.length} remote events will be deleted"

    # Add new events.
    to_add.each { |new_event|
      add_event(http, api_key, *new_event)
    }

    to_update.each { |existing_event|
      update_event(http, api_key, *existing_event)
    }

    remote_events.each { |old_event|
      delete(http, api_key, old_event)
    }
  end

  def local_to_params(local_event, identifier)
    puts local_event[:time].iso8601
    {
        "activity" => {
            "title" => local_event[:title],
            "description" => local_event[:description],
            "location" => local_event[:location],
            "address" => local_event[:locationlink],
            "advertise" => true,
            "association" => "zeus",
            "sync_data" => identifier,
            "start_time" => local_event[:time].iso8601,
            "end_time" => local_event[:end].iso8601,
            "infolink" => "https://zeus.ugent.be#{local_event.path}"
        }
    }
  end

  def update_event(http, api_key, identifier, remote_event, local_event)
    params = local_to_params(local_event, identifier)

    uri = URI("#{DSA_API}/#{remote_event["id"]}")

    req = Net::HTTP::Put.new(uri)
    req['Authorization'] = api_key
    req['Content-Type'] = 'application/json'
    req.body = params.to_json

    response = http.request(req)

    case response
    when Net::HTTPSuccess
      puts "Updated event #{remote_event["id"]}"
    when Net::HTTPUnauthorized
      raise "#{response.message}: username and password set and correct?"
    when Net::HTTPServerError
      raise "#{response.message}: try again later?"
    else
      raise response.message
    end
  end

  def add_event(http, api_key, identifier, local_event)
    params = local_to_params(local_event, identifier)

    uri = URI(DSA_API)

    req = Net::HTTP::Post.new(uri)
    req['Authorization'] = api_key
    req['Content-Type'] = 'application/json'
    req.body = params.to_json
    response = http.request(req)

    case response
    when Net::HTTPSuccess
      puts "Added event #{identifier}"
    when Net::HTTPUnauthorized
      raise "#{response.message}: username and password set and correct?"
    when Net::HTTPServerError
      raise "#{response.message}: try again later?"
    else
      print response.body
      raise response.message
    end
  end

  def delete(http, api_key, remote)
    uri = URI("#{DSA_API}/#{remote["id"]}")

    req = Net::HTTP::Delete.new(uri)
    req['Authorization'] = api_key

    response = http.request(req)

    case response
    when Net::HTTPSuccess
      puts "Delete event #{remote["id"]}"
    when Net::HTTPUnauthorized
      raise "#{response.message}: username and password set and correct?"
    when Net::HTTPServerError
      raise "#{response.message}: try again later?"
    else
      raise response.message
    end
  end

  def filter_items(items, cut_off)
    # Must be in the future
    # Must have sync_id
    items.find_all('/events/*/*.md')
        .find_all { |event| event[:time] > cut_off }
        .find_all { |event| event[:exclude_from_sync] != true }
  end

  def get_server_events(http, api_key, cut_off)
    uri = URI(DSA_API)
    params = {:start_time => cut_off.iso8601, :association => "zeus"}
    uri.query = URI.encode_www_form(params)

    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = api_key
    response = http.request(request)

    case response
    when Net::HTTPSuccess
      JSON.parse response.body
    when Net::HTTPUnauthorized
      raise "#{response.message}: username and password set and correct?"
    when Net::HTTPServerError
      raise "#{response.message}: try again later?"
    else
      raise response.message
    end
  end
end

runner SyncRunner
