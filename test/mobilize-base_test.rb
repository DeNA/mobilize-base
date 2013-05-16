require 'test_helper'

describe "Mobilize" do

  it "tests is_due? methods" do
    puts "testing is_due?"
    TestHelper.restart_test_redis
    TestHelper.drop_test_db

    u = TestHelper.owner_user
    gdrive_slot = u.email
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
      assert expected == j.is_due?
    end
  end

  it "runs integration test" do

    puts "restart test redis"
    TestHelper.restart_test_redis
    TestHelper.drop_test_db

    puts "restart workers"
    Mobilize::Jobtracker.restart_workers!

    u = TestHelper.owner_user
    r = u.runner
    user_name = u.name
    gdrive_slot = u.email

    puts "build test runner"
    TestHelper.build_test_runner(user_name)
    assert Mobilize::Jobtracker.workers.length == Mobilize::Resque.config['max_workers'].to_i

    puts "add base1_stage1.in sheet"
    input_fixture_name = "base1_stage1.in"
    input_target_url = "gsheet://#{r.title}/#{input_fixture_name}"
    TestHelper.write_fixture(input_fixture_name, input_target_url, 'replace')

    puts "add jobs sheet with integration jobs"
    jobs_fixture_name = "integration_jobs"
    jobs_target_url = "gsheet://#{r.title}/jobs"
    TestHelper.write_fixture(jobs_fixture_name, jobs_target_url, 'update')

    puts "wait for stages"
    Mobilize::Jobtracker.start
    #wait for stages to complete
    expected_fixture_name = "integration_expected"
    TestHelper.confirm_expected_jobs(expected_fixture_name)

    puts "jobtracker posted test sheet data to test destination, and checksum succeeded?"
    tsv_hash = {}
    ["base1_stage1.in", "base1_stage2.out", "base2_stage1.err"].each do |sheet_name|
      url = "gsheet://#{r.title}/#{sheet_name}"
      data = Mobilize::Dataset.read_by_url(url,user_name,gdrive_slot)
      tsv_hash[sheet_name] = data
    end

    assert tsv_hash["base1_stage2.out"] == tsv_hash["base1_stage1.in"]

    base3_response = tsv_hash["base2_stage1.err"].tsv_to_hash_array.first['response']
    assert base3_response == "Unable to parse stage params, make sure you don't have issues with your quotes, commas, or colons."

  end
end
