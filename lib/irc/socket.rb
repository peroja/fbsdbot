require 'socket'
require 'thread'

module FBSDBot
  module IRC
  
    # originally stolen from http://github.com/apeiros/silverplatter-irc/tree/master
    class Socket

      # A single space character
      Space   = " ".freeze
      # AWAY command
      AWAY    = "AWAY".freeze
      # JOIN command
      JOIN    = "JOIN".freeze
      # KICK command
      KICK    = "KICK".freeze
      # MODE command
      MODE    = "MODE".freeze
      # NICK command
      NICK    = "NICK".freeze
      # NOTICE command
      NOTICE  = "NOTICE".freeze
      # NS command
      NS      = "NS".freeze
      # PART command
      PART    = "PART".freeze
      # PASS command
      PASS    = "PASS".freeze
      # PING command
      PING    = "PING".freeze
      # PONG command
      PONG    = "PONG".freeze
      # PRIVMSG command
      PRIVMSG = "PRIVMSG".freeze
      # USER command
      USER    = "USER".freeze
      # QUIT command
      QUIT    = "QUIT".freeze
      # WHO command
      WHO     = "WHO".freeze
      # WHOIS command
      WHOIS   = "WHOIS".freeze

      # server the instance is linked with
      attr_reader :server

      # port used for connection
      attr_reader :port

      # the own host (nil if not supported)
      attr_reader :host

      # end-of-line used for communication
      attr_reader :eol
  
      # contains counters:
      # :read_lines:: Number of lines that have been read.
      # :read_bytes:: Number of bytes that have been read.
      # :sent_lines:: Number of lines that have been sent.
      # :sent_bytes:: Number of bytes that have been sent.
      attr_reader :count
  
      # contains limits for the protocol, burst times/counts etc.
      attr_reader :limit
      
      # log raw out, will use log_out.puts(raw)
      attr_accessor :log_out
      
      DefaultOptions = {
        :port => 6667,
        :eol  => "\r\n".freeze,
        :host => nil,
      }
      
      def initialize(server, options={})
        options       = DefaultOptions.merge(options)
        @logger       = options.delete(:log)
        @server       = server
        @port         = options.delete(:port)
        @eol          = options.delete(:eol).dup.freeze
        @host         = options[:host] ? options.delete(:host).dup.freeze : options.delete(:host)
        @log_out      = nil
        @last_sent    = Time.new
        @count        = Hash.new(0)
        @limit        = {
          :message_length => 300, # max. length of a text message (e.g. in notice, privmsg) sent to server
          :raw_length     => 400, # max. length of a raw message sent to server
          :burst          => 4,   # max. messages that can be sent with send_delay (0 = infinite)
          :burst2         => 20,  # max. messages that can be sent with send_delay (0 = infinite)
          :send_delay     => 0.1, # minimum delay between each message
          :burst_delay    => 1.5, # delay after a burst
          :burst2_delay   => 15,  # delay after a burst2
        }
        @limit.each { |key, default|
          @limit[key] = options.delete(key) if options.has_key?(key)
        }
        @mutex        = Mutex.new
        @socket       = nil
        @connected    = false
        raise ArgumentError, "Unknown arguments: #{options.keys.inspect}" unless options.empty?
      end

      # Whether this Socket is currently connected to a server or not.
      def connected?
        @connected
      end

      # connects to the server
      def connect
        info("Connecting to #{@server} on port #{@port} from #{@host || '<default>'}")
        @socket = TCPSocket.open(@server, @port, @host)
        info("Successfully connected")
      rescue ArgumentError => error
        if @host then
          warn("host-parameter is not supported by your ruby version. Parameter discarted.")
          @host = nil
          retry
        else
          raise
        end
      rescue Interrupt
        raise
      rescue Exception
        error("Connection failed.")
        raise
      else
        @connected = true
      end

      # get next message from server, blocking, returns nil if closed
      def read
        if m = @socket.gets(@eol) then
          @count[:read_lines] += 1
          @count[:read_bytes] += m.size
          # m.chomp(@eol)
          m
        else
          @connected = false
          nil
        end
      rescue IOError
        @connected = false
        nil
      end
      
      # Send a raw message to irc, eol will be appended
      # Use specialized methods instead if possible since they will releave
      # you from several tasks like translating newlines, take care of overlength
      # messages etc.
      def write_with_eol(data)
        p :writing => data
        @mutex.synchronize {
          warn("Raw too long (#{data.length} instead of #{@limit[:raw_length]})") if (data.length > @limit[:raw_length])
          now = Time.now
    
          # keep delay between single (bursted) messages
          sleeptime = @limit[:send_delay]-(now-@last_sent)
          if sleeptime > 0 then
            sleep(sleeptime)
            now += sleeptime
          end
          
          # keep delay after a burst (1)
          if (@count[:burst] >= @limit[:burst]) then
            sleeptime = @limit[:burst_delay]-(now-@last_sent)
            if sleeptime > 0 then
              sleep(sleeptime)
              now += sleeptime
            end
            @count[:burst]  = 0
          end
    
          # keep delay after a burst (2)
          if (@count[:burst2] >= @limit[:burst2]) then
            sleeptime = @limit[:burst2_delay]-(now-@last_sent)
            if sleeptime > 0 then
              sleep(sleeptime)
              now += sleeptime
            end
            @count[:burst2] = 0
          end
    
          # send data and update data
          @last_sent  = Time.new
          data       += @eol
          @socket.write(data)
          @count[:burst]      += 1
          @count[:burst2]     += 1
          @count[:sent_lines] += 1
          @count[:sent_bytes] += data.length
          @log_out.puts(data) if @log_out
        }
      rescue IOError
        error("Writing #{data.inspect} failed")
        raise
      end 
  
      def send_raw(*arguments)
        if arguments.last.include?(Space) || arguments.last[0] == ?: then
          arguments[-1] = ":#{arguments.last}"
        end
        write_with_eol(arguments.join(Space))
      end

      # log into the irc-server (and connect if necessary)
      def login(nickname, username, realname, serverpass=nil)
        connect unless @connected
        send_raw(PASS, serverpass) if serverpass
        send_raw(NICK, nickname)
        send_raw(USER, username, "0", "*", realname)
      end
  
      # identify nickname to nickserv
      # FIXME: figure out what the server supports, possibly requires it
      # to be moved to SilverPlatter::IRC::Connection (to allow ghosting, nickchange, identify)
      def send_identify(password)
        send_raw(NS, "IDENTIFY #{password}")
      end
      
      # FIXME: figure out what the server supports, possibly requires it
      # to be moved to SilverPlatter::IRC::Connection (to allow ghosting, nickchange, identify)
      def send_ghost(nickname, password)
        send_raw(NS, "GHOST #{nickname} #{password}")
      end
      
      # cuts the message-text into pieces of a maximum size
      # (or until the next newline if shorter)
      def normalize_message(message, limit=nil, &block)
        message.scan(/[^\n\r]{1,#{limit||@limit[:message_length]}}/, &block)
      end
  
      # sends a privmsg to given user or channel (or multiple)
      # messages containing newline or exceeding @limit[:message_length] are automatically splitted
      # into multiple messages.
      def send_privmsg(message, *recipients)
        normalize_message(message) { |message|
          recipients.each { |recipient|
            send_raw(PRIVMSG, recipient, message)
          }
        }
      end
  
      # same as privmsg except it's formatted for ACTION
      def send_action(message, *recipients)
        normalize_message(message) { |message|
          recipients.each { |recipient|
            send_raw(PRIVMSG, recipient, "\001ACTION #{message}\001")
          }
        }
      end
  
      # sends a notice to receiver (or multiple if receiver is array of receivers)
      # formatted=true allows usage of ![]-format commands (see IRCmessage.getFormatted)
      # messages containing newline automatically get splitted up into multiple messages.
      # Too long messages will be tokenized into fitting sized messages (see @limit[:message_length])
      def send_notice(message, *recipients)
        normalize_message(message) { |message|
          recipients.each { |recipient|
            send_raw(NOTICE, recipient, message)
          }
        }
      end
  
      # send a ping
      def send_ping(*args)
        send_raw(PING, *args)
      end
  
      # send a pong
      def send_pong(*args)
        send_raw(PONG, *args)
      end
  
      # join specified channels
      # use an array [channel, password] to join password-protected channels
      # returns the channels joined.
      # ==Synopsis
      #   irc.send_join("#foo", "#bar")
      #   irc.send_join(["#foo", "pass_for_foo"])
      #   require 'silverplatter/irc/string'
      #   irc.send_join("#foo".with_password("foopass"))
      def send_join(*channels)
        channels.map { |channel, password|
          if password then
            send_raw(JOIN, channel, password)
          else
            send_raw(JOIN, channel)
          end
          channel
        } # need to map to get rid of the passwords
      end
  
      # part specified channels
      # returns the channels parted from.
      def send_part(reason=nil, *channels)
        if channels.empty?
          channels = [reason]
          reason   = nil
        end # FIXME: leave this overloading in place or remove?
        reason ||= "leaving"

        # some servers still can't process lists of channels in part
        channels.each { |channel|
          send_raw(PART, channel, reason)
        } # each returns receiver
      end
  
      # set your own nick
      # does NO verification/validation of any kind
      def send_nick(nick)
        send_raw(NICK, nick)
      end
  
      # set your status to away with reason 'reason'
      def send_away(reason="")
        return back if reason.empty?
        send_raw(AWAY, reason)
      end
  
      # reset your away status to back
      def send_back
        send_raw(AWAY)
      end
  
      # kick user in channel with reason
      def send_kick(user, channel, reason)
        send_raw(KICK, channel, user, reason)
      end
      
      # send a mode command to a channel
      def send_mode(channel, *mode)
        if mode.empty? then
          send_raw(MODE, channel)
        else
          send_raw(MODE, channel, *mode)
        end
      end
      
      # Give Op to user in channel
      # User can be a nick or IRC::User, either one or an array.
      def send_multiple_mode(channel, pre, flag, targets)
        (0...targets.length).step(12) { |i|
          slice = targets[i,12]
          send_raw(MODE, channel, "#{pre}#{flag*slice.length}", *slice)
        }
      end
  
      # Give Op to user in channel
      # User can be a nick or IRC::User, either one or an array.
      def send_op(channel, *users)
        send_multiple_mode(channel, '+', 'o', users)
      end
  
      # Take Op from user in channel
      # User can be a nick or IRC::User, either one or an array.
      def send_deop(channel, *users)
        send_multiple_mode(channel, '-', 'o', users)
      end
  
      # Give voice to user in channel
      # User can be a nick or IRC::User, either one or an array.
      def send_voice(channel, *users)
        send_multiple_mode(channel, '+', 'v', users)
      end
  
      # Take voice from user in channel.
      # User can be a nick or IRC::User, either one or an array.
      def send_devoice(channel, *users)
        send_multiple_mode(channel, '-', 'v', users)
      end
  
      # Set ban in channel to mask
      def send_ban(channel, *masks)
        send_multiple_mode(channel, '+', 'b', masks)
      end
  
      # Remove ban in channel to mask
      def send_unban(channel, *masks)
        send_multiple_mode(channel, '-', 'b', masks)
      end

      # Send a "who" to channel/user
      def send_who(target)
        send_raw(WHO, target)
      end
  
      # Send a "whois" to server
      def send_whois(nick)
        send_raw(WHOIS, nick)
      end
  
      # send the quit message to the server
      def send_quit(reason=nil)
        send_raw(QUIT, reason || "leaving")
      end
      
      # send the quit message to the server
      # unless you set close to false it will also close the socket
      def quit(reason="leaving", close=true)
        send_quit(reason)
        close() if close
      end
  
      # closes the connection to the irc-server
      def close
        @socket.close
      end
      
      def inspect # :nodoc:
        sprintf "#<%s:0x%08x %s:%s from %s using '%s', stats: %s>",
          self.class,
          object_id<<1,
          @server,
          @port,
          @host || "<default>",
          @eol.inspect[1..-2],
          @count.inspect
        # /sprintf
      end
      
      private
      
      # create a Logger instance?
      def info(msg)
        log :info, msg
      end
      
      def error(msg)
        log :error, msg
      end
      
      def warn(msg)
        log :warn, msg
      end
      
      def log(type, msg)
        puts "#{Time.now} :: #{type} - #{msg}"
      end
    end
    
  end
end
