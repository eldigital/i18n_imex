require 'yaml'
require 'csv'

module I18nImex
  class Export

    attr_accessor :locale_dir, :export_dir, :locales, :default_locale, :source_format, :files, :export_hash

    def initialize(options = {})
      # path to directory of source-locale-files
      self.locale_dir     = options[:locale_dir] || "#{Rails.root}/config/locales"

      # path to directory of target-locale-files and target-csv-files
      self.export_dir     = options[:export_dir] || "#{Rails.root}/config/locales"

      # format of source-files (usually yml or json)
      self.source_format  = options[:src_format] || 'yml'

      # hash of source-locale-files which will be exported
      # format: { locale: [file, ... , file] }
      self.files          = {}

      # hash of arbitrarily nested keys which will be exported
      # format: { locale: { key: { key: value } } }
      self.export_hash    = {}

      # 'master'-locale which defines which locale-files should act as 'blueprint', usually :de
      self.default_locale = options[:default_locale] || I18n.default_locale

      # Array of all unique locales which will be exported
      self.locales        = ([self.default_locale] + (options[:locales] || I18n.available_locales)).uniq

      # initialize the files to be exported
      get_files
    end

    # main-method
    # for each locale and locale-file to export build according csv-file
    def run
      locales.each do |locale|
        # checking that all files / keys exist for any non.default locale
        self.files[locale].each do |file|
          build_hash(file)
          create_csv(file, locale)
        end
      end
    end

    private

    # does two things
    # first:
    # get all paths for all files which will be exported defined by locales
    # build Hash for these paths separated by locales
    # second:
    # create a locale-file for each default-locale-file if it does not exist yet
    # e.g. default is :de, other locales are :en, :sv, admin.de.yml exists but admin.en.yml and admin.sv.yml don't
    def get_files
      self.locales.each do |l|
        self.files[l] = Dir.glob("#{self.locale_dir}/*#{l}.#{self.source_format}")

        next if l == self.default_locale

        self.files[self.default_locale].each do |original_file|
          locale_file = original_file.gsub("#{self.default_locale}.#{self.source_format}", "#{l}.#{self.source_format}")

          next if self.files[l].include?(locale_file)

          create_locale_file(locale_file, original_file)

          self.files[l] << locale_file
        end
      end
    end

    def create_locale_file(locale_file, original_file)
      case source_format
      when 'yml'
        original   = YAML.load(File.open(original_file))
        new_locale = { l.to_s => original[self.default_locale.to_s] }
        File.open(locale_file, 'w') {|f| f.puts YAML.dump(new_locale) }
      when 'json'
        original   = JSON.load(File.open(original_file))
        File.open(locale_file, 'w') {|f| f.puts JSON.pretty_generate(original) }
      end
    end

    # creates the target-csv-file with the content from the source-locale-file
    # uses the previously built export-hash
    def create_csv(file, locale)
      CSV.open(export_name(file), 'w', col_sep: ';') do |csv|
        csv << headers
        # get the according source-locale-file, e.g. de.yml if en.yml
        default_locale_file = change_locale_name(get_filename(file), locale, self.default_locale)

        # build the csv from the according export-hash-part of this default-source
        export_hash[default_locale_file].keys.sort.each do |key|

          locale_key = key.gsub(Regexp.new("\\b#{self.default_locale}\\."), "#{locale}.")

          # add key and value from default-source if they don't exist and mark them explicitly as missing
          if export_hash[get_filename(file)][locale_key].nil?
            puts "adding key: #{locale_key}"
            csv << [locale_key, export_hash[default_locale_file][key], "X", ""]
          # otherwise take key and value from source and mark explicitly as unchanged if they are not different
          else
            csv << [
              locale_key, export_hash[get_filename(file)][locale_key], "",
              (export_hash[default_locale_file][key] == export_hash[get_filename(file)][locale_key] ? 'X' : '')
            ]
          end
        end
      end
    end

    # returns the last part of a given path which should be the name of the file
    def get_filename(file)
      File.basename(file)
    end

    def change_locale_name(file, from, to)
      file.gsub("#{from}.#{self.source_format}", "#{to}.#{self.source_format}")
    end

    # builds a target-hash for each source-locale-file
    # takes a path to a source-locale-file as parameter
    # adds a key for each file and builds a hash of all keys and their values recursivly
    # example: { 'my_locale_file.en.yml': { my.key: 'my value' } }
    def build_hash(file)
      filename = get_filename(file)
      self.export_hash[filename] = {}
      case source_format
      when 'yml'
        traverse(YAML.load(File.open(file))) { |keys, value| export_hash[filename][keys * '.'] = value }
      when 'json'
        traverse(JSON.load(File.open(file))) { |keys, value| export_hash[filename][keys * '.'] = value }
      end
    end

    # clever piece of recursive magic
    def traverse(obj, keys = [], &block)
      case obj
      when Hash
        obj.each do |k,v|
          keys << k
          traverse(v, keys, &block)
          keys.pop
        end
      when Array
        obj.each { |v| traverse(obj, keys, &block) }
      else
        yield keys, obj
      end
    end

    # builds path for target-export-file
    # creates export-directory if necessary
    def export_name(file)
      d = "#{self.export_dir}/csv"
      FileUtils.mkdir_p(d)
      name = get_filename(file) + ".csv"
      File.join(d, name)
    end

    # the headers for each target-csv-file
    # YAML_KEY  - the name  of the key
    # VALUE     - the value of the related key
    # MISSING   - hint if key was missing in source-locale-file
    # UNCHANGED - hint if
    def headers
      %w[YAML_KEY VALUE MISSING UNCHANGED]
    end

  end
end
