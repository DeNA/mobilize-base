module Mobilize
  module Log
    def Log.config
      Base.config('log')
    end

    def Log.max_size
      Log.config['max_size']
    end

    def Log.header_length
      Log.config['header_length']
    end

    def Log.write(path, method, message)
      session = Mongoid.session(:default)
      timestamp = Time.now.to_f.to_s.split(".").instance_eval{|ta| [Time.at(ta.first.to_i).utc.to_s,ta.last[0..5]].join(" ")}
      header = "#{timestamp} #{path}/#{method}: #{message[0..Log.header_length-1]}"
      session[:mobilize_logs].insert(timestamp: timestamp, path: path, method: method, header: header, message: message)
    end

    def Log.tail
      db_name = Mongoid.session(:default).options[:database]
      db = Mongo::Connection.new().db(db_name)
      coll = db.collection('mobilize_logs')
      cursor = Mongo::Cursor.new(coll, :tailable => true)
      loop do
        if doc = cursor.next_document
          puts doc['header']
        else
          sleep 1
        end
      end
    end

    def Log.refresh
      #drop and recreate capped Log collection
      session = Mongoid.session(:default)
      session[:mobilize_logs].drop
      session.command(create: "mobilize_logs", capped: true, size: Log.max_size)
    end
  end
end
