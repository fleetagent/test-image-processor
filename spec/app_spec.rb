require "spec_helper"
require "redis"

# Create a simple mock Redis object before Queue is loaded,
# since Queue::REDIS is assigned at class load time.
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

# Intercept Redis.new so Queue::REDIS gets our mock
module RedisNewOverride
  def new(*)
    MOCK_REDIS
  end
end

Redis.singleton_class.prepend(RedisNewOverride)

require_relative "../app"

RSpec.describe ImageProcessor::App do
  include Rack::Test::Methods

  def app
    ImageProcessor::App
  end

  before do
    MOCK_REDIS.store.clear
    MOCK_REDIS.lists.clear
  end

  describe "GET /health" do
    it "returns 200 with status ok" do
      get "/health"

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("ok")
    end

    it "responds with JSON content type" do
      get "/health"

      expect(last_response.content_type).to include("application/json")
    end
  end

  describe "POST /api/resize" do
    it "returns 202 with a jobId" do
      post "/api/resize", { sourceUrl: "https://example.com/photo.jpg" }.to_json, "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(202)
      body = JSON.parse(last_response.body)
      expect(body["jobId"]).to match(/\A[0-9a-f-]{36}\z/)
      expect(body["status"]).to eq("queued")
    end

    it "stores the job in Redis" do
      post "/api/resize", { sourceUrl: "https://example.com/photo.jpg" }.to_json, "CONTENT_TYPE" => "application/json"

      body = JSON.parse(last_response.body)
      job_id = body["jobId"]

      raw = MOCK_REDIS.get("job:#{job_id}")
      expect(raw).not_to be_nil
      job = JSON.parse(raw)
      expect(job["type"]).to eq("resize")
      expect(job["status"]).to eq("queued")
    end

    it "pushes the job id onto the pending list" do
      post "/api/resize", { sourceUrl: "https://example.com/photo.jpg" }.to_json, "CONTENT_TYPE" => "application/json"

      body = JSON.parse(last_response.body)
      expect(MOCK_REDIS.lists["jobs:pending"]).to include(body["jobId"])
    end

    it "uses default widths [200, 400, 800] and format webp when not specified" do
      post "/api/resize", { sourceUrl: "https://example.com/photo.jpg" }.to_json, "CONTENT_TYPE" => "application/json"

      body = JSON.parse(last_response.body)
      raw = MOCK_REDIS.get("job:#{body["jobId"]}")
      job = JSON.parse(raw)
      expect(job["payload"]["widths"]).to eq([200, 400, 800])
      expect(job["payload"]["format"]).to eq("webp")
    end

    it "uses custom widths and format when specified" do
      post "/api/resize", { sourceUrl: "https://example.com/photo.jpg", widths: [100, 300], format: "png" }.to_json, "CONTENT_TYPE" => "application/json"

      body = JSON.parse(last_response.body)
      raw = MOCK_REDIS.get("job:#{body["jobId"]}")
      job = JSON.parse(raw)
      expect(job["payload"]["widths"]).to eq([100, 300])
      expect(job["payload"]["format"]).to eq("png")
    end
  end

  describe "POST /api/optimize" do
    it "returns 202 with a jobId" do
      post "/api/optimize", { sourceUrl: "https://example.com/photo.jpg" }.to_json, "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(202)
      body = JSON.parse(last_response.body)
      expect(body["jobId"]).to match(/\A[0-9a-f-]{36}\z/)
      expect(body["status"]).to eq("queued")
    end

    it "uses default quality of 80 when not specified" do
      post "/api/optimize", { sourceUrl: "https://example.com/photo.jpg" }.to_json, "CONTENT_TYPE" => "application/json"

      body = JSON.parse(last_response.body)
      raw = MOCK_REDIS.get("job:#{body["jobId"]}")
      job = JSON.parse(raw)
      expect(job["payload"]["quality"]).to eq(80)
    end

    it "accepts custom quality" do
      post "/api/optimize", { sourceUrl: "https://example.com/photo.jpg", quality: 60 }.to_json, "CONTENT_TYPE" => "application/json"

      body = JSON.parse(last_response.body)
      raw = MOCK_REDIS.get("job:#{body["jobId"]}")
      job = JSON.parse(raw)
      expect(job["payload"]["quality"]).to eq(60)
    end
  end

  describe "GET /api/jobs/:id" do
    it "returns 200 with job data for a known job" do
      job_data = { id: "abc-123", type: "resize", status: "queued", payload: {} }.to_json
      MOCK_REDIS.set("job:abc-123", job_data)

      get "/api/jobs/abc-123"

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["id"]).to eq("abc-123")
      expect(body["type"]).to eq("resize")
      expect(body["status"]).to eq("queued")
    end

    it "returns 404 for an unknown job" do
      get "/api/jobs/unknown-id"

      expect(last_response.status).to eq(404)
      body = JSON.parse(last_response.body)
      expect(body["error"]).to eq("Job not found")
    end
  end
end
