require 'json'
require 'byebug'

# read a .json file with yaml header, make the json available for editing and saving
class JekyllJSON
  attr_accessor :json

  def initialize(path)
    @path = path
    @raw_yaml, @raw_json = File.read(@path).match(/(---\n.+?\n---\n)(.*)/m)[1..2]
    @json = JSON.parse(@raw_json)
  end

  def save
    File.open(@path, 'w') do |f|
      f.write(@raw_yaml)
      f.write("\n")
      f.write(@json.to_json)
    end
  end
end

namespace :postwax do
  desc "Merge image-level manifests to create item-level manifests"
  task "merge_manifests" do
    canvases = []

    manifests = Dir['img/derivatives/iiif/*/manifest.json'] # TODO: get list from data file, to keep order
    output_manifest = nil
    manifests.sort.each do |source_file| # note: sortying by file name
      source_json = JekyllJSON.new(source_file).json
      if output_manifest
        output_manifest['sequences'][0]['canvases'] << source_json['sequences'][0]['canvases'][0]
      else output_manifest
        output_manifest = source_json # note that the first canvas is kept here
      end
    end
    # set item as paged
    output_manifest['viewingHint'] = 'paged'
    # TODO: manage metadata and filename for item-level manifest
    File.open('img/derivatives/iiif/bigitem.json', 'w') { |f| f.write("---\nlayout: none\n---\n" + output_manifest.to_json) }
  end

  desc "Generate 90-width thumbnails, as requested by Universal Viewer"
  task "level0_workarounds" do
    require 'mini_magick'
    require 'fileutils'

    # TODO: incorporate new thumbs into list of sizes in info.json
    images = Dir['img/derivatives/iiif/images/*']
    images.each do |image_path|
      thumb_path = "#{image_path}/full/90,/0"
      FileUtils.mkdir_p(thumb_path)
      thumb_file = "#{thumb_path}/default.jpg"
      image = nil
      unless File.file?(thumb_file)
        image = MiniMagick::Image.open("#{image_path}/full/full/0/default.jpg")
        image.resize('90x')
        image.write(thumb_file)
      end

      # if the thumb already existed, open it so we can determine the height
      image ||= MiniMagick::Image.open(thumb_file)
      new_size = { width: image.width, height: image.height }

      # append the new size to the array of sizes in info.json, if not already there
      info = JekyllJSON.new("#{image_path}/info.json")
      next if info.json['sizes'].include?(new_size)

      info.json['sizes'] << new_size
      info.save

      # copy 0,0,max-x,max-y images to full
      full_area = "#{image_path}/0,0,#{info.json['width']},#{info.json['height']}/."
      full = "#{image_path}/full"
      FileUtils.cp_r(full_area, full)
    end

  end
end
