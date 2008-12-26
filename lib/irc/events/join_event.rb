module FBSDBot
  class JoinEvent < Event

    attr_reader :nick, :user, :host, :channel
    
    def initialize(conn, opts = {})
      super(conn)
      @nick    = opts[:nick]
      @user    = opts[:user]
      @host    = opts[:host]
      @channel = opts[:params].first
    end
    
  end
end