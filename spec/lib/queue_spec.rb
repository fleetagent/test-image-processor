require "spec_helper"
require "securerandom"

# app_spec.rb loads first (alphabetical), so Queue is already loaded
# with MOCK_REDIS. If this file runs standalone, we need to load it.
unless defined?(MOCK_REDIS)
  require "redis"

  class MockRedis
    attr_reader :store, :lists

    def initialize
      @store = {}
      @lists = Hash.new { |h, k| h[k] = [] }
    end

    def set(key, value)
      @store[key] = value
    end

    def get(key)
      @store[key]
    end

    def lpush(key, value)
      @lists[key].unshift(value)
    end
  end

  MOCK_REDIS = MockRedis.new

  module RedisNewOverride
    def new(*)
      MOCK_REDIS
    end
  end

  Redis.singleton_class.prepend(RedisNewOverride)
end

require_relative "../../lib/queue"

RSpec.describe ImageProcessor::Queue do
  before do
    MOCK_REDIS.store.clear
    MOCK_REDIS.lists.clear
  end

  describe ".enqueue" do
    it "returns a UUID job id" do
      job_id = described_class.enqueue("resize", { source_url: "https://example.com/img.jpg" })

      expect(job_id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it "stores the job in Redis under the correct key" do
      job_id = described_class.enqueue("resize", { source_url: "https://example.com/img.jpg" })

      raw = MOCK_REDIS.get("job:#{job_id}")
      expect(raw).not_to be_nil
    end

    it "stores job data with correct type, payload, and status" do
      job_id = described_class.enqueue("optimize", { quality: 80 })

      raw = MOCK_REDIS.get("job:#{job_id}")
      job = JSON.parse(raw)
      expect(job["id"]).to eq(job_id)
      expect(job["type"]).to eq("optimize")
      expect(job["payload"]["quality"]).to eq(80)
      expect(job["status"]).to eq("queued")
      expect(job).to have_key("created_at")
    end

    it "pushes the job id onto the pending list" do
      job_id = described_class.enqueue("resize", {})

      expect(MOCK_REDIS.lists["jobs:pending"]).to include(job_id)
    end

    it "returns unique ids for successive calls" do
      id1 = described_class.enqueue("resize", {})
      id2 = described_class.enqueue("resize", {})

      expect(id1).not_to eq(id2)
    end
  end

  describe ".get_job" do
    it "returns parsed job data when the job exists" do
      stored = { id: "abc-123", type: "resize", status: "queued", payload: { widths: [200] } }.to_json
      MOCK_REDIS.set("job:abc-123", stored)

      result = described_class.get_job("abc-123")

      expect(result).to be_a(Hash)
      expect(result["id"]).to eq("abc-123")
      expect(result["type"]).to eq("resize")
      expect(result["payload"]["widths"]).to eq([200])
    end

    it "returns nil when the job does not exist" do
      result = described_class.get_job("nonexistent")

      expect(result).to be_nil
    end

    it "returns data that was stored via enqueue" do
      job_id = described_class.enqueue("optimize", { quality: 90 })

      result = described_class.get_job(job_id)

      expect(result["id"]).to eq(job_id)
      expect(result["type"]).to eq("optimize")
      expect(result["payload"]["quality"]).to eq(90)
    end
  end
end
