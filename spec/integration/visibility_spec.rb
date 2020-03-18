describe 'visibilty', set_app: true do
  let(:repo)     { Repository.where(owner_name: 'svenfuchs', name: 'minimal').first }
  let(:requests) { repo.requests.order(:id) }
  let(:builds)   { repo.builds.order(:id) }
  let(:jobs)     { Job.where(repository_id: repo.id).order(:id) }
  let(:response) { send(method, path, {}, { 'HTTP_ACCEPT' => 'application/vnd.travis-ci.2.1+json' }) }
  let(:status)   { response.status }
  let(:body)     { JSON.parse(response.body).deep_symbolize_keys }
  let(:job_id)   { 42864 }
  let(:archived_content) { 'hello world!'}
  let(:xml_content) {
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
    <ListBucketResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\">
    <Name>bucket</Name>
    <Prefix/>
    <Marker/>
    <MaxKeys>1000</MaxKeys>
    <IsTruncated>false</IsTruncated>
      <Contents>
          <Key>jobs/#{job_id}/log.txt</Key>
          <LastModified>2009-10-12T17:50:30.000Z</LastModified>
          <ETag>&quot;hgb9dede5f27731c9771645a39863328&quot;</ETag>
          <Size>20308738</Size>
          <StorageClass>STANDARD</StorageClass>
          <Owner>
              <ID>75aa57f09aa0c8caeab4f8c24e99d10f8e7faeebf76c078efc7c6caea54ba06a</ID>
              <DisplayName>mtd@amazon.com</DisplayName>
          </Owner>
      </Contents>
    </ListBucketResult>"
  }

  before { repo.update_attributes(private: false) }
  before { requests.update_all(private: true) }
  before { builds.update_all(private: true) }
  before { jobs.update_all(private: true) }
  before { requests[0].update_attributes(private: false) }
  before { builds[0].update_attributes(private: false) }
  before { jobs[0].update_attributes(private: false) }
  before :each do
    stub_request(:get, %r(https://s3\.amazonaws\.com/archive\.travis-ci\.(org|com)/\?prefix=jobs/\d+/log.txt)).
      to_return(status: 200, body: xml_content, headers: {})
    stub_request(:get, %r(https://bucket\.s3\.amazonaws\.com/jobs/\d+/log.txt)).
      to_return(status: 200, body: archived_content, headers: {})

    Fog.mock!
    storage = Fog::Storage.new({
      aws_access_key_id: 'key',
      aws_secret_access_key: 'secret',
      provider: 'AWS'
    })
    bucket = storage.directories.create(key: 'archive.travis-ci.org')
    file = bucket.files.create(
      key: "jobs/#{job_id}/log.txt",
      body: archived_content
    )

    allow_any_instance_of(Travis::RemoteLog::ArchiveClient).to receive(:fetch_archived).and_return(file)
  end

  after do
    Fog.unmock!
    Fog::Mock.reset
  end

  let(:public_request)  { requests[0] }
  let(:public_build)    { builds[0] }
  let(:public_job)      { jobs[0] }
  let(:private_request) { requests[2] }
  let(:private_build)   { builds[2] }
  let(:private_job)     { jobs[2] }

  before { Travis.config.host = 'travis-ci.com' }
  before { Travis.config.public_mode = true }

  before { stub_request(:get, %r(logs/#{public_job.id}\?by=job_id)).to_return(status: 200, body: %({"job_id": #{public_job.id} })) }
  before { stub_request(:get, %r(logs/1\?by=id)).to_return(status: 200, body: %({"job_id": #{public_job.id} })) }
  before { stub_request(:get, %r(logs/2\?by=id)).to_return(status: 200, body: %({"job_id": #{private_job.id} })) }

  describe 'GET /branches?ids=%{public_build.id} needs to be filtered (returns list of builds)' do
    it { expect(body[:branches].size).to eq 1 }
    it { expect(body[:branches].map { |b| b[:id] }).to eq [public_build.id] }
  end

  describe 'GET /branches?ids=%{private_build.id} needs to be filtered (returns list of builds)' do
    it { expect(body[:branches].size).to eq 0 }
  end

  describe 'GET /branches?repository_id=%{repo.id} needs to be filtered (returns list of builds)' do
    it { expect(body[:branches].size).to eq 0 } # TODO should be 1
    xit { expect(body[:branches].map { |b| b[:id] }).to eq [public_build.id] }
  end

  describe 'GET /repos/%{repo.id}/branches needs to be filtered (returns list of builds)' do
    it { expect(body[:branches].size).to eq 0 } # TODO should be 1
    xit { expect(body[:branches].map { |b| b[:id] }).to eq [public_build.id] }
  end

  describe 'GET /repos/%{repo.slug}/branches needs to be filtered (returns list of builds)' do
    it { expect(body[:branches].size).to eq 0 } # TODO should be 1
    xit { expect(body[:branches].map { |b| b[:id] }).to eq [public_build.id] }
  end

  describe 'GET /repos/%{repo.id}/branches/master needs to check visibility' do
    before { Build.where(private: false).delete_all }
    it { expect(status).to eq 404 }
  end

  describe 'GET /builds needs to be filtered' do
    it { expect(body[:builds].size).to eq 0 }
    xit { expect(body[:builds].map { |b| b[:id] }).to eq [public_build.id] }
  end

  describe 'GET /builds?repository_id=%{repo.id} needs to be filtered' do
    it { expect(body[:builds].size).to eq 1 }
    it { expect(body[:builds].map { |b| b[:id] }).to eq [public_build.id] }
  end

  describe 'GET /builds?repository_id=%{repo.id}&branches=master' do
    before { Build.where(private: false).delete_all }
    it { expect(body[:builds].size).to eq 0 }
  end

  describe 'GET /builds?repository_id=%{repo.id}&branches=%{private_build.branch} needs to be filtered' do
    it { expect(body[:builds].size).to eq 0 } # TODO should be 1
    xit { expect(body[:builds].map { |b| b[:id] }).to eq [public_build.id] }
  end

  describe 'GET /repos/%{repo.id}/builds needs to be filtered' do
    xit { expect(body[:builds].size).to eq 1 } # does not seem to exist?
  end

  describe 'GET /repos/%{repo.slug}/builds needs to be filtered' do
    it { expect(body[:builds].size).to eq 1 }
    it { expect(body[:builds].map { |b| b[:id] }).to eq [public_build.id] }
  end

  describe 'GET /repos/%{repo.slug}/builds?branches=master needs to be filtered (returns list of builds)' do
    it { expect(body[:builds].size).to eq 1 } # it seems params[:branches] is now unused? the local var `name` is not used on that endpoint any more
    it { expect(body[:builds].map { |b| b[:id] }).to eq [public_build.id] }
  end

  describe 'GET /builds?running=true' do
    before { builds.update_all(state: :started) }
    it { expect(body[:builds].size).to eq 0 }
    xit { expect(body[:builds].map { |b| b[:id] }).to eq [public_build.id] }
  end

  describe 'GET /builds/%{public_build.id} needs to check visibility' do
    it { expect(status).to eq 200 }
  end

  describe 'GET /builds/%{private_build.id} needs to check visibility' do
    it { expect(status).to eq 404 }
  end

  describe 'GET /repos/%{repo.slug}/builds/%{public_build.id} needs to check visibility' do
    it { expect(status).to eq 200 }
  end

  describe 'GET /repos/%{repo.id}/builds/%{private_build.id} needs to check visibility' do
    it { expect(status).to eq 404 }
  end

  describe 'GET /jobs/%{public_job.id} needs to check visibility' do
    it { expect(status).to eq 200 }
  end

  describe 'GET /jobs/%{private_job.id} needs to check visibility' do
    it { expect(status).to eq 404 }
  end

  describe 'GET /jobs/%{public_job.id}/log needs to check visibility' do
    it { expect(status).to eq 200 }
  end

  describe 'GET /jobs/%{private_job.id}/log needs to check visibility' do
    it { expect(status).to eq 404 }
  end

  describe 'GET /logs/1 needs to check visibility' do
    it { expect(status).to eq 200 }
  end

  describe 'GET /logs/2 needs to check visibility' do
    it { expect(status).to eq 404 }
  end

  describe 'GET /requests/%{public_request.id} needs to check visibility' do
    it { expect(status).to eq 200 }
  end

  describe 'GET /requests/%{private_request.id} needs to check visibility' do
    it { expect(status).to eq 404 }
  end

  describe 'GET /requests?repository_id=%{repo.id} needs to be filtered' do
    it { expect(body[:requests].size).to eq 1 }
    it { expect(body[:requests].map { |r| r[:id] }).to eq [public_request.id] }
  end

  describe 'GET /repos' do
    it { expect(status).to eq 401 }
  end

  describe 'GET /repos/%{repo.id}' do
    before { repo.update_attributes(private: true) }
    it { expect(status).to eq 404 }
  end

  describe 'GET /repos/%{repo.id}/caches' do
    before { repo.update_attributes(private: true) }
    it { expect(status).to eq 404 }
  end

  describe 'GET /repos/%{repo.slug}' do
    before { repo.update_attributes(private: true) }
    it { expect(status).to eq 404 }
  end

  describe 'GET /repos/svenfuchs' do
    it { expect(body[:repos].map { |r| r[:slug] }).to eq ['svenfuchs/minimal'] }
    it { expect(body[:repos].map { |r| r[:slug] }).to_not include 'josevalim/enginex' }
    it { expect(Repository.where(owner_name: 'josevalim').count).to eq 1 }
  end

  # <Project
  #   name="svenfuchs/minimal"
  #   activity="Building"
  #   lastBuildStatus="Unknown"
  #   lastBuildLabel="3"
  #   lastBuildTime=""
  #   webUrl="https://www.example.com/svenfuchs/minimal" />

  describe 'GET /repos/%{repo.id}/cc.xml' do
    before { builds.update_all(state: :started) }
    it { expect(status).to eq 200 }
    it { expect(response.body).to include('svenfuchs/minimal') }
    it { expect(response.body).to_not include(private_build.id.to_s) }
  end

  describe 'GET /repos/%{user.login}.xml'  do
  end

  # <?xml version="1.0" encoding="utf-8"?>
  # <feed xmlns="http://www.w3.org/2005/Atom">
  #   <title>svenfuchs/minimal Builds</title>
  #   <link href="http://example.org/repo_status/svenfuchs/minimal/builds" type="application/atom+xml" rel = "self" />
  #   <id>repo:1</id>
  #   <rights>Copyright (c) 2018 Travis CI GmbH</rights>
  #   <updated>2018-05-01T16:19:57+02:00</updated>
  #   <entry>
  #     <title>svenfuchs/minimal Build #1</title>
  #     <link href="https://travis-ci.com/svenfuchs/minimal/builds/72077" />
  #     <id>repo:1:build:72077</id>
  #     <updated>2018-05-01T14:20:02+00:00</updated>
  #     <summary type="html">
  #     &lt;p&gt;
  #       add Gemfile (Sven Fuchs)
  #       &lt;br/&gt;&lt;br/&gt;
  #       State: failed
  #       &lt;br/&gt;
  #       Started at: 2010-11-12 12:00:00 UTC
  #       &lt;br/&gt;
  #       Finished at: 2010-11-12 12:00:10 UTC
  #     &lt;/p&gt;
  #     </summary>
  #     <author>
  #       <name>Sven Fuchs</name>
  #     </author>
  #   </entry>
  # </feed>

  describe 'GET /repos/%{repo.slug}/builds.atom' do
    it { expect(response.body).to include("build:#{public_build.id.to_s}") }
    it { expect(response.body).to_not include("build:#{private_build.id.to_s}") }
  end

  def method
    example_group_description.split(' ').first.downcase
  end

  def path
    interpolate(self, example_group_description.split(' ')[1])
  end

  def interpolate(obj, str)
    str % Hash.new { |_, key| key.to_s.split('.').inject(obj) { |o, key| o.send(key) } }
  end

  def example_group_description
    RSpec.current_example.example_group.description
  end
end
