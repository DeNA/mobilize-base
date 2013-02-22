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
    jobs_sheet = r.gsheet(gdrive_slot)
    tsv = jobs_sheet.read(user_name)
    assert tsv.tsv_header_array.join.length == 53 #total header length

    puts "add base1_stage1 input sheet"
    test_source_sheet = Mobilize::Gsheet.find_or_create_by_path("#{r.path.split("/")[0..-2].join("/")}/base1_stage1.in",gdrive_slot)

    test_source_ha = ::YAML.load_file("#{Mobilize::Base.root}/test/base1_stage1.yml")*40
    test_source_tsv = test_source_ha.hash_array_to_tsv
    test_source_sheet.write(test_source_tsv,user_name)

    puts "add row to jobs sheet, wait 180s"
    test_job_rows = ::YAML.load_file("#{Mobilize::Base.root}/test/base_job_rows.yml")
    jobs_sheet.add_or_update_rows(test_job_rows)
    sleep 180

    puts "jobtracker posted test sheet data to test destination, and checksum succeeded?"
    test_target_sheet_1 = Mobilize::Gsheet.find_by_path("#{r.path.split("/")[0..-2].join("/")}/base1.out",gdrive_slot)
    test_target_sheet_2 = Mobilize::Gsheet.find_by_path("#{r.path.split("/")[0..-2].join("/")}/base2.out",gdrive_slot)

    assert test_target_sheet_1.read(user_name) == test_source_sheet.read(user_name)

    puts "delete both output sheets, set first job to active=true, wait 120s"
    [test_target_sheet_1,test_target_sheet_2].each{|s| s.delete}

    jobs_sheet.add_or_update_rows([{'name'=>'base1','active'=>true}])
    sleep 180

    test_target_sheet_2 = Mobilize::Gsheet.find_by_path("#{r.path.split("/")[0..-2].join("/")}/base2.out",gdrive_slot)
    puts "jobtracker posted test sheet data to test destination, and checksum succeeded?"
    assert test_target_sheet_2.read(user_name)  == test_source_sheet.read(user_name)

  end

end
