require 'test_helper'
describe Mobilize do

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
    #stop jobtracker
    Mobilize::Jobtracker.stop!

    puts "jobtracker posted test sheet data to test destination, and checksum succeeded?"
    tsv_hash = {}
    ["base1_stage1.in", "base1_stage2.out"].each do |sheet_name|
      url = "gsheet://#{r.title}/#{sheet_name}"
      data = Mobilize::Dataset.read_by_url(url,user_name,gdrive_slot)
      assert TestHelper.check_output(url, 'min_length' => 10) == true
      tsv_hash[sheet_name] = data
    end

    assert tsv_hash["base1_stage2.out"] == tsv_hash["base1_stage1.in"]

    err_url = "gsheet://#{r.title}/base2_stage1.err"
    err_response = "Unable to parse stage params, make sure you don't have issues with your quotes, commas, or colons."

    assert TestHelper.check_output(err_url, 'match' => err_response) == true

  end
end
