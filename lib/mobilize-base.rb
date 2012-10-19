require "mobilize-base/version"
require "mobilize-base/extensions/array"
require "mobilize-base/extensions/hash"
require "mobilize-base/extensions/object"
require "mobilize-base/extensions/string"

module Mobilize
  module Base
    def self.root
      File.expand_path('../..', __FILE__)+"/lib/mobilize-base"
    end
    # Your code goes here...
  end
end

require "mobilize-base/jobtracker"
require "mobilize-base/mongo"
require "mobilize-base/models/dataset"
require "mobilize-base/models/requestor"
require "mobilize-base/models/job"


#require "mobilize-base/handlers/*"
#require "mobilize-base/models/*"
