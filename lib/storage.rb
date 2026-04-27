require "aws-sdk-s3"

module ImageProcessor
  class Storage
    def initialize
      @client = Aws::S3::Client.new(
        region: ENV.fetch("AWS_REGION", "eu-west-1")
      )
      @bucket = ENV.fetch("S3_BUCKET", "fleet-images")
    end

    def upload(key, file_path, content_type = "image/webp")
      File.open(file_path, "rb") do |file|
        @client.put_object(bucket: @bucket, key: key, body: file, content_type: content_type)
      end
      "s3://#{@bucket}/#{key}"
    end

    def download(key, dest_path)
      @client.get_object(bucket: @bucket, key: key, response_target: dest_path)
      dest_path
    end
  end
end
