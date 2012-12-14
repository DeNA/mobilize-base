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
    tsv = jobs_sheet.to_tsv
    assert tsv.length == 56 #headers only

    puts "add base1_task1 input sheet"
    test_source_sheet = Mobilize::Gsheet.find_or_create_by_path("#{r.path.split("/")[0..-2].join("/")}/base1_task1.in",gdrive_slot)

    test_source_ha = ::YAML.load_file("#{Mobilize::Base.root}/test/base1_task1.yml")*40
    test_source_tsv = test_source_ha.hash_array_to_tsv
    test_source_sheet.write(test_source_tsv)

    puts "add row to jobs sheet, wait 120s"
    test_job_rows = ::YAML.load_file("#{Mobilize::Base.root}/test/base_job_rows.yml")
    jobs_sheet.add_or_update_rows(test_job_rows)
    sleep 120

    puts "jobtracker posted test sheet data to test destination, and checksum succeeded?"
    test_target_sheet_1 = Mobilize::Gsheet.find_by_path("#{r.path.split("/")[0..-2].join("/")}/base1.out",gdrive_slot)
    test_target_sheet_1 = Mobilize::Gsheet.find_by_path("#{r.path.split("/")[0..-2].join("/")}/base1.out",gdrive_slot)


    assert test_target_sheet_1.to_tsv == test_source_sheet.to_tsv

    puts "delete both output sheets, set first job to active=true"
    test_target_sheet_1.delete

    jobs_sheet.add_or_update_rows([{'name'=>'base1','active'=>true}])
    sleep 90
    
    test_target_sheet_2 = Mobilize::Gsheet.find_by_path("#{r.path.split("/")[0..-2].join("/")}/base1.out",gdrive_slot)
    puts "jobtracker posted test sheet data to test destination, and checksum succeeded?"
    assert test_target_sheet_2.to_tsv == test_source_sheet.to_tsv

  end

end
