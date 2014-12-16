require 'json'
require 'date'
require 'time'

require File.expand_path(File.dirname(__FILE__) + '/error')
require File.expand_path(File.dirname(__FILE__) + '/configure')
require File.expand_path(File.dirname(__FILE__) + '/active_support')

module Timezone
  class Zone
    include Comparable
    attr_reader :rules, :zone

    SOURCE_BIT = 0
    NAME_BIT = 1
    DST_BIT = 2
    OFFSET_BIT = 3

    ZONE_FILE_PATH = File.expand_path(File.dirname(__FILE__)+'/../../data')

    # Create a new Timezone object.
    #
    #   Timezone.new(options)
    #
    # :zone       - The actual name of the zone. For example, Australia/Sydney or Americas/Los_Angeles.
    # :lat, :lon  - The latitude and longitude of the location.
    # :latlon     - The array of latitude and longitude of the location.
    #
    # If a latitude and longitude is passed in, the Timezone object will do a lookup for the actual zone
    # name and then use that as a reference. It will then load the appropriate json timezone information
    # for that zone, and compile a list of the timezone rules.
    def initialize options
      if options.has_key?(:lat) && options.has_key?(:lon)
        options[:zone] = timezone_id options[:lat], options[:lon]
      elsif options.has_key?(:latlon)
        options[:zone] = timezone_id *options[:latlon]
      end

      raise Timezone::Error::NilZone, 'No zone was found. Please specify a zone.' if options[:zone].nil?

      data = get_zone_data(options[:zone])

      @rules = []

      data.split("\n").each do |line|
        source, name, dst, offset = line.split(':')
        source = source.to_i
        dst = dst == '1'
        offset = offset.to_i
        source = @rules.last[SOURCE_BIT]+source if @rules.last
        @rules << [source, name, dst, offset]
      end

      @zone = options[:zone]
    end

    def active_support_time_zone
      @active_support_time_zone ||= Timezone::ActiveSupport.format(@zone)
    end

    # Determine the time in the timezone.
    #
    #   timezone.time(reference)
    #
    # reference - The Time you want to convert.
    #
    # The reference is converted to a UTC equivalent. That UTC equivalent is then used to lookup the appropriate
    # offset in the timezone rules. Once the offset has been found that offset is added to the reference UTC time
    # to calculate the reference time in the timezone.
    def time(reference)
      reference.utc + utc_offset(reference)
    end

    # Determine the time in the timezone w/ the appropriate offset.
    #
    #     timezone.time_with_offset(reference)
    #
    # reference - the `Time` you want to convert.
    #
    # The reference is converted to a UTC equivalent. That UTC equivalent is
    # then used to lookup the appropriate offset in the timezone rules. Once the
    # offset has been found, that offset is added to the reference UTC time
    # to calculate the reference time in the timezone. The offset is then
    # appended to put the time object into the proper offset.
    def time_with_offset(reference)
      utc = time(reference)
      offset = utc_offset(reference)
      Time.new(utc.year, utc.month, utc.day, utc.hour, utc.min, utc.sec, offset)
    end

    # Whether or not the time in the timezone is in DST.
    def dst?(reference)
      rule_for_reference(reference)[DST_BIT]
    end

    # Get the current UTC offset in seconds for this timezone.
    #
    #   timezone.utc_offset(reference)
    def utc_offset(reference=Time.now)
      rule_for_reference(reference)[OFFSET_BIT]
    end

    def <=>(zone) #:nodoc:
      utc_offset <=> zone.utc_offset
    end

    class << self
      # Instantly grab all possible time zone names.
      def names
        @@names ||= Dir[File.join(ZONE_FILE_PATH, "**/**/*")].collect do |file|
          file.gsub("#{ZONE_FILE_PATH}/", '')
        end
      end

      # Get a list of specified timezones and the basic information accompanying that zone
      #
      #   zones = Timezone::Zone.list(*zones)
      #
      # zones - An array of timezone names. (i.e. Timezone::Zones.list("America/Chicago", "Australia/Sydney"))
      #
      # The result is a Hash of timezones with their title, offset in seconds, UTC offset, and if it uses DST.
      #
      def list(*args)
        args = nil if args.empty? # set to nil if no args are provided
        zones = args || Configure.default_for_list || self.names # get default list
        list = self.names.select { |name| zones.include? name } # only select zones if they exist

        @zones = []
        now = Time.now
        list.each do |zone|
          item = Zone.new(zone: zone)
          @zones << {
            :zone => item.zone,
            :title => Configure.replacements[item.zone] || item.zone,
            :offset => item.utc_offset,
            :utc_offset => (item.utc_offset/(60*60)),
            :dst => item.dst?(now)
          }
        end
        @zones.sort_by! { |zone| zone[Configure.order_list_by] }
      end
    end

  private

  # Retrieve the data from a particular time zone
  def get_zone_data(zone)
    file = File.join(ZONE_FILE_PATH, zone)

    if !File.exists?(file)
      raise Timezone::Error::InvalidZone, "'#{zone}' is not a valid zone."
    end

    File.read(file)
  end

    def rule_for_reference reference
      reference = reference.utc.to_i
      @rules.each do |rule|
        return rule if reference <= rule[SOURCE_BIT]
      end

      @rules.last if !@rules.empty? && reference >= @rules.last[SOURCE_BIT]
    end

    def timezone_id lat, lon #:nodoc:
      Timezone::Configure.lookup.lookup(lat,lon)
    end
  end
end
