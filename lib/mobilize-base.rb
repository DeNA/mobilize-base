require "mobilize-base/version"

module Mobilize
  module Base
    def self.root_dir
      File.expand_path('../..', __FILE__)+"/lib/mobilize-base/"
    end
    # Your code goes here...
  end
end
require "mobilize-base/mongo"
