require 'test_helper'

describe "Mobilize" do
  it "runs integration test" do

    puts "restart test redis"
    TestHelper.restart_test_redis

    puts "clear out test db"
    TestHelper.drop_test_db

    puts "restart workers"
    Mobilize::Jobtracker.restart_workers!

    u = TestHelper.owner_user
    user_name = u.name
    gdrive_slot = u.email

    puts "build test runner"
    TestHelper.build_test_runner(user_name)
    assert Mobilize::Jobtracker.workers.length == Mobilize::Resque.config['max_workers'].to_i

    puts "Jobtracker created runner with 'jobs' sheet?"

    r = u.runner
    jobs_sheet_url = "gsheet://#{r.path}"
    jobs_sheet = Mobilize::Gsheet.find_by_path(r.path,gdrive_slot)
    jobs_sheet_dst = Mobilize::Dataset.find_or_create_by_url(jobs_sheet_url)
    jobs_sheet_tsv = jobs_sheet_dst.read(user_name,gdrive_slot)

    assert jobs_sheet_tsv.tsv_header_array.join.length == 53 #total header length

    puts "add base1 input file"
    test_filename = "test_base_1"
    file_url = "gfile://#{test_filename}.tsv"
    test_source_ha = ::YAML.load_file("#{Mobilize::Base.root}/test/#{test_filename}.yml")*40
    test_source_tsv = test_source_ha.hash_array_to_tsv
    Mobilize::Dataset.write_by_url(file_url,test_source_tsv,user_name)
    rem_tsv = Mobilize::Dataset.read_by_url(file_url,user_name)
    assert rem_tsv == test_source_tsv

    puts "add row to jobs sheet, wait for stages"
    test_job_rows = ::YAML.load_file("#{Mobilize::Base.root}/test/base_job_rows.yml")
    jobs_sheet.reload
    jobs_sheet.add_or_update_rows(test_job_rows)
    #wait for stages to complete
    TestHelper.wait_for_stages

    puts "jobtracker posted test sheet data to test destination, and checksum succeeded?"
    tsv_hash = {}
    ["base1.out", "base2.out", "base3_stage1.err"].each do |sheet_name|
      url = "gsheet://#{r.title}/#{sheet_name}"
      data = Mobilize::Dataset.read_by_url(url,user_name,gdrive_slot)
      tsv_hash[sheet_name] = data
    end

    assert tsv_hash["base1.out"].to_s.length>0
    assert tsv_hash["base2.out"] == tsv_hash["base1.out"]

    base3_response = tsv_hash["base3_stage1.err"].tsv_to_hash_array.first['response']
    assert base3_response == "Unable to parse stage params, make sure you don't have issues with your quotes, commas, or colons."

    Mobilize::Jobtracker.stop!
  end
end
