require 'test_helper'
require 'mocha/setup'

class TestUnit < MiniTest::Unit::TestCase
  def self.test_order
    :sorted
  end

  def self.setup_test
    TestHelper.restart_test_redis
    TestHelper.drop_test_db
  end

  def self.define_tests(fixture)
    u = TestHelper.owner_user
    TestHelper.load_fixture(fixture).each_with_index do |jh, i|
      name = "%03d_%s" % [i, jh['name']]
      define_method(:"test_#{name}") do
        job_path = "#{u.runner.path}/#{jh['name']}"
        j = Mobilize::Job.find_or_create_by_path(job_path)
        #update job params
        j.update_from_hash(jh)
        #apply the completed_at, failed at, and parent attributes where appropriate
        if jh['completed_at']
          j.stages.last.update_attributes(:completed_at=>eval(jh['completed_at']))
        end
        if jh['failed_at']
          j.stages.last.update_attributes(:failed_at=>eval(jh['failed_at']))
        end
        if jh['parent']
          j.parent.stages.last.update_attributes(:completed_at=>eval(jh['parent']['completed_at'])) if jh['parent']['completed_at']
          j.parent.stages.last.update_attributes(:failed_at=>eval(jh['parent']['failed_at'])) if jh['parent']['failed_at']
        end
        if jh['now']
          Time.stubs(:now).returns(eval(jh['now']))
        end
        expected = jh['expected']
        #check if is_due
        assert expected == j.is_due?
      end
    end
  end

  setup_test
  define_tests("is_due")
end
