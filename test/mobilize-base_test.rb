require 'test_helper'

describe "Mobilize" do

  def before
    puts 'nothing before'
  end

  # enqueues 4 workers on Resque
  it "runs integration test" do

    puts "restart test redis"
    Mobilize::Jobtracker.restart_test_redis

    puts "clear out test db"
    Mobilize::Jobtracker.drop_test_db

    puts "restart workers"
    Mobilize::Jobtracker.restart_workers!

    puts "build test runner"
    gdrive_slot = Mobilize::Gdrive.owner_email
    puts "create user 'mobilize'"
    user_name = gdrive_slot.split("@").first
    u = Mobilize::User.find_or_create_by_name(user_name)
    assert u.email == gdrive_slot

    Mobilize::Jobtracker.build_test_runner(user_name)
    assert Mobilize::Jobtracker.workers.length == Mobilize::Resque.config['max_workers'].to_i

    puts "Jobtracker created runner with 'jobs' sheet?"
    r = u.runner
    jobs_sheet_url = "gsheet://#{r.path}"
    jobs_sheet_dst = Mobilize::Dataset.find_or_create_by_url(jobs_sheet_url)
    jobs_sheet_tsv = jobs_sheet_dst.read(user_name,gdrive_slot)
    assert jobs_sheet_tsv.tsv_header_array.join.length == 53 #total header length

    puts "add base1 input file"
    test_filename = "test_base_1"
    file_url = "gfile://#{test_filename}.tsv"
    test_source_ha = ::YAML.load_file("#{Mobilize::Base.root}/test/#{test_filename}.yml")*40
    test_source_tsv = test_source_ha.hash_array_to_tsv
    Mobilize::Dataset.write_by_url(file_url,test_source_tsv,user_name)

    puts "add row to jobs sheet, wait for stages"
    test_job_rows = ::YAML.load_file("#{Mobilize::Base.root}/test/base_job_rows.yml")
    jobs_sheet = Mobilize::Gsheet.find_by_path(r.path,gdrive_slot)
    jobs_sheet.add_or_update_rows(test_job_rows)
    #wait for stages to complete
    wait_for_stages

    puts "jobtracker posted test sheet data to test destination, and checksum succeeded?"
    test_target_sheet_1_url = "gsheet://#{r.title}/base1.out"
    test_target_sheet_2_url = "gsheet://#{r.title}/base2.out"
    test_error_sheet_url = "gsheet://#{r.title}/base1_stage1.err"

    test_1_tsv = Mobilize::Dataset.read_by_url(test_target_sheet_1_url,user_name,gdrive_slot)
    test_2_tsv = Mobilize::Dataset.read_by_url(test_target_sheet_1_url,user_name,gdrive_slot)

    assert test_1_tsv == test_2_tsv

    puts "change first job to fail, wait for stages"
    test_job_rows.first['stage1'] = %{gsheet.write source:"gfile://test_base_1.fail", target:base1.out, retries:3}
    Mobilize::Dataset.write_by_url(test_error_sheet_url," ",user_name,gdrive_slot)
    jobs_sheet.add_or_update_rows(test_job_rows)

    #wait for stages to complete
    wait_for_stages

    test_error_sheet = Mobilize::Gsheet.find_by_path("#{r.path.split("/")[0..-2].join("/")}/base1_stage1.err",gdrive_slot)
    puts "jobtracker posted failing test error to sheet "
    error_rows = test_error_sheet.read(user_name).tsv_to_hash_array
    assert error_rows.first['response'] == "No data found in gfile://test_base_1.fail"
    Mobilize::Jobtracker.stop!
  end

  def wait_for_stages(time_limit=600,stage_limit=120,wait_length=10)
    time = 0
    time_since_stage = 0
    #check for 10 min
    while time < time_limit and time_since_stage < stage_limit
      sleep wait_length
      job_classes = Mobilize::Resque.jobs.map{|j| j['class']}
      if job_classes.include?("Mobilize::Stage")
        time_since_stage = 0
        puts "saw stage at #{time.to_s} seconds"
      else
        time_since_stage += wait_length
        puts "#{time_since_stage.to_s} seconds since stage seen"
      end
      time += wait_length
      puts "total wait time #{time.to_s} seconds"
    end

    if time >= time_limit
      raise "Timed out before stage completion"
    end
  end
end
