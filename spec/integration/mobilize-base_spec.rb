require 'spec_helper'
describe Mobilize::Base do
  before(:all) do
    restart_test_redis
    drop_test_db
    puts "restart workers"
    Mobilize::Jobtracker.restart_workers!
  end

  let(:u) { owner_user }
  let(:r) { u.runner }
  let(:user_name) { u.name }
  let(:gdrive_slot) { u.email }

  it "build test runner" do
    build_test_runner(user_name)
    worker_length = Mobilize::Jobtracker.workers.length
    expect(worker_length).to eq(Mobilize::Resque.config['max_workers'].to_i)
  end

  it "add base1_stage1.in sheet" do
    input_fixture_name = "base1_stage1.in"
    input_target_url = "gsheet://#{r.title}/#{input_fixture_name}"
    expect(write_fixture(input_fixture_name, input_target_url, 'replace' => true)).to be_true
  end

  it "add jobs sheet with integration jobs" do
    jobs_fixture_name = "integration_jobs"
    jobs_target_url = "gsheet://#{r.title}/jobs"
    expect(write_fixture(jobs_fixture_name, jobs_target_url, 'update' => true)).to be_true
  end

  it "wait for stages" do
    Mobilize::Jobtracker.start
    #wait for stages to complete
    expected_fixture_name = "integration_expected"
    expect(confirm_expected_jobs(expected_fixture_name)).to be_true
    #stop jobtracker
    Mobilize::Jobtracker.stop!
  end

  it "check output" do
    tsv_hash = {}
    ["base1_stage1.in", "base1_stage2.out"].each do |sheet_name|
      url = "gsheet://#{r.title}/#{sheet_name}"
      data = Mobilize::Dataset.read_by_url(url,user_name,gdrive_slot)
      expect(output(url).length).to be >= 10
      tsv_hash[sheet_name] = data
    end
    expect(tsv_hash["base1_stage2.out"]).to eq(tsv_hash["base1_stage1.in"])

    err_url = "gsheet://#{r.title}/base2_stage1.err"
    err_response = "Unable to parse stage params, make sure you don't have issues with your quotes, commas, or colons."
    expect(output(err_url)).to eq("response\n#{err_response}")
  end
end
