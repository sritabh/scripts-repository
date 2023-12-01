require 'fileutils'
require 'yaml'
require 'json'

def delete_subdirectory(directory_path)
  if File.directory?(directory_path)
    FileUtils.rm_rf(directory_path)
    puts "Subdirectory #{directory_path} has been deleted."
  else
    puts "Error: #{directory_path} is not a valid directory."
  end
end

def list_subdirectories(directory_path)
  # Check if the provided path is a directory
  if File.directory?(directory_path)
    # Get a list of all subdirectories in the specified directory
    subdirectories = Dir.entries(directory_path).select { |entry| File.directory?(File.join(directory_path, entry)) && entry != "." && entry != ".." }

    return subdirectories
  else
    puts "Error: #{directory_path} is not a valid directory."
    return []
  end
end

COURSES_DIR_PATH = "./courses"
BOOKS_DIR_PATH = "./books"

## STEP 1: Keep only the courses available in books(which were imported)
# Remove all subdirectories in the "courses" directory that are not in the "books" directory
def keep_courses_from_book_only
  # List all subdirectories in the "courses" directory
  available_courses = list_subdirectories(COURSES_DIR_PATH)
  available_books = list_subdirectories(BOOKS_DIR_PATH)

  available_courses.each do |course|
    if !available_books.include?(course)
      delete_subdirectory(File.join(COURSES_DIR_PATH, course))
    end
  end
end
#DONE
# keep_courses_from_book_only


def extract_chapter_info(file_path)
  # Read the YAML front matter from the Markdown file
  front_matter = File.read(file_path).match(/\A---(.*?)\n---/m)

  if front_matter
    # Parse the YAML front matter
    front_matter_data = YAML.safe_load(front_matter[1])
    images = extract_image_info(file_path)

    cleaned_id = front_matter_data['id'].gsub(/^(ch|CH)-\d{2}-/, '').sub(/\.md$/, '')
    # Extract relevant information
    {
      filename: File.basename(file_path),
      id: cleaned_id,
      title: front_matter_data['title'],
      images: {
        count: images.count,
        alt_data: images,
      },
    }
  else
    puts "Error: YAML front matter not found in #{file_path}. Skipping this file."
    nil
  end
end

def extract_image_info(chapter_path)
  markdown_content = File.read(chapter_path)

  pattern = /\!\[([^\]]*)\]\(([^)]*)\)/

  matches = markdown_content.scan(pattern)


  image_info = matches.map do |match|
    filename = match[0] == "Alt text" ? File.basename(match[1].split(" ").first) : File.basename(match[1])
    alt = match[0] == "Alt text" ? match[1].match(/"([^"]*)"/)[1] : match[0]
    info = {}
    info[filename] = alt
    info
  end


end

def extract_books_data(directory_path)
  # Initialize an array to store book information
  books = {}

  # Traverse each subdirectory in the specified directory
  Dir.foreach(directory_path) do |subdirectory|
    next if subdirectory == '.' || subdirectory == '..'
    subdirectory_path = File.join(directory_path, subdirectory)
    book_details = {
      chapters_count: 0,
      chapters: [],
    }

    # Check if the entry is a directory
    if File.directory?(subdirectory_path)
      lessons_directory = File.join(subdirectory_path, '_lessons')

      next unless File.directory?(lessons_directory)

      # Traverse each Markdown file in the subdirectory
      Dir.glob(File.join(lessons_directory, '*.md')) do |markdown_file|
        # Extract book information from the Markdown file
        chapter_info = extract_chapter_info(markdown_file)
        # Add the book information to the array
        book_details[:chapters] << chapter_info if chapter_info
        book_details[:chapters_count] += 1
      end
    end
    books[subdirectory] =  book_details
  end

  books
end


OUTPUT_BOOK_DATA_FILE = "./extracted_books_data.json"

#Step 2
# Extracting to json data for manual cleaning if required
# extracted_books = extract_books_data(BOOKS_DIR_PATH)

# output_json_file = "./extracted_books_data.json"
# File.open(output_json_file, 'w') { |file| file.write(JSON.pretty_generate(extracted_books)) }

# puts "Book information extracted and saved to #{output_json_file}."

#Step 3
# Reading books under courses directory

## Adding alt tag to image in courses
def run()
  def get_alt_value(image, old_course_chapters)
    old_course_chapters.each do |chapter|
      images_data = chapter["images"]["alt_data"]
      images_data.each do |alt_data|
        return alt_data[image] if alt_data.include?(image)
      end

    end
    return nil
  end

  def extract_images_from_file(content)

    image_files = content.scan(/<image>(.*?)<\/image>/).flatten
    image_files
  end

  course_alt_data = {}
  courses_update_stats = []
  Dir.foreach(COURSES_DIR_PATH) do |subdirectory|
    next if subdirectory == '.' || subdirectory == '..'
    course_path = File.join(COURSES_DIR_PATH, subdirectory)
    assets_path = File.join(course_path, 'assets.yml')

    course = subdirectory
    asset_data = YAML.load_file(assets_path)
    course_images = asset_data['images']

    books_data = File.open(OUTPUT_BOOK_DATA_FILE) { |f| JSON.load(f) }

    course_alt_data[course] = {} #Building data for use
    old_course_chapters = books_data[course]["chapters"]
    course_images.each do |image|
      alt_value = get_alt_value(image, old_course_chapters)
      course_alt_data[course][image] = alt_value
      # puts "For image: #{image}"
      # puts "Alt value: #{alt_value}"
      # puts "----------------------------------"
    end

    course_chapters_path = File.join(course_path, 'chapters')

    course_update_stats = {
      name: course,
      total_images_tags: 0,
      updated_images_tage_with_alt: 0,
    }
    Dir.glob(File.join(course_chapters_path, '*')) do |course_dir|
      next unless File.directory?(course_dir)

      # Read index.md file in each course directory
      index_md_path = File.join(course_dir, 'index.md')
      next unless File.exist?(index_md_path)

      content = File.read(index_md_path)
      image_files = extract_images_from_file(content)

      course_update_stats[:total_images_tags]+=image_files.count
      updated_content = content
      total_alt_added = 0
      image_files.each do |image|
        image_tag = "<image>#{image}</image>"
        next unless course_alt_data[course][image]
        total_alt_added+=1
        updated_content = updated_content.gsub(image_tag, "<image alt=\"#{course_alt_data[course][image]}\">#{image}</image>")
      end

      course_update_stats[:updated_images_tage_with_alt]+=total_alt_added
      ### WARNING: UPDATING THE FILES ###
      File.open(index_md_path, 'w') { |file| file.write(updated_content) }

    end

    courses_update_stats << course_update_stats
  end

  courses_update_stats.each do |stats_data|
    puts "-------------------------------------"
    puts "Course name: #{stats_data[:name]}"
    puts "- Total images tags : #{stats_data[:total_images_tags]}"
    puts "- Updated images tags with alt: #{stats_data[:updated_images_tage_with_alt]}"
  end
  puts "================================="
  puts "Total images tags: #{courses_update_stats.sum { |stats| stats[:total_images_tags] }}"
  puts "Total images tags updated with alt: #{courses_update_stats.sum { |stats| stats[:updated_images_tage_with_alt] }}"
end

run()
