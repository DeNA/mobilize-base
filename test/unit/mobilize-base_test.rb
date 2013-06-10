require 'test_helper'
class TestUnit < MiniTest::Unit::TestCase
  def setup
    TestHelper.restart_test_redis
    TestHelper.drop_test_db
  end

  #this test checks that several job triggers work as expected
  def test_is_due
    u = TestHelper.owner_user
    job_hashes = TestHelper.load_fixture("is_due")
    job_hashes.each do |jh|
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
      expected = jh['expected']
      #check if is_due
      puts "checking #{j.name}"
      assert expected == j.is_due?
    end
  end
end
