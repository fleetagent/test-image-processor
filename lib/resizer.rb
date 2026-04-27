require "mini_magick"

module ImageProcessor
  class Resizer
    def self.resize(input_path, output_path, width, format = "webp")
      image = MiniMagick::Image.open(input_path)
      image.resize "#{width}x"
      image.format format
      image.write output_path
      { width: image.width, height: image.height, size: File.size(output_path) }
    end

    def self.optimize(input_path, output_path, quality = 80)
      image = MiniMagick::Image.open(input_path)
      image.quality quality.to_s
      image.strip
      image.write output_path
      { size: File.size(output_path), quality: quality }
    end
  end
end
