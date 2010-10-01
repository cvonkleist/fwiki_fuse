require 'fwiki_fuse'

describe FwikiFuse do
  before(:each) do
    @f = FwikiFuse.new(nil, nil, nil, nil)
  end

  def fake_response(code, body)
    response = mock('response')
    response.stub!(:code).and_return code
    response.stub!(:read_body).and_return body
    response
  end

  it 'should get directory listing' do
    body = <<-EOF
    <html>
      <ul id="pages">
        <li><a href="/home">home</a></li>
        <li><a href="/asdf">asdf&lt;</a></li>
      </ul>
    </html>
    EOF
    @f.stub!(:get).and_return fake_response('200', body)
    (@f.contents('/') - %w(home asdf<)).should == []
  end

  it 'should raise error if cannot get directory listing' do
    @f.stub!(:get).and_return fake_response('500', '')
    lambda { @f.contents('/') }.should raise_error(Errno::ENOENT)
  end

  it 'should check the existence of a file' do
    @f.stub!(:sizes).and_return 'foo' => 1337
    @f.file?('/foo').should be_true
    @f.file?('/bar').should be_false
  end

  it 'should write a file' do
    @f.should_receive(:put).and_return fake_response('200', '')
    @f.write_to('/foo', 'bar')
  end

  it 'should raise error on failure to write file' do
    @f.should_receive(:put).and_return fake_response('500', '')
    lambda { @f.write_to('/foo', 'bar') }.should raise_error(Errno::EAGAIN)
  end

  it 'should cache data' do
    class FwikiFuse
      def random
        cache(nil) do
          rand(100000)
        end
      end
    end
    random = @f.random
    @f.random.should == random
  end
end
