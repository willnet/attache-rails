require "cgi"
require "uri"
require "httpclient"

module AttacheRails
  module Utils
    class << self
      def attache_upload_and_get_json(readable)
        uri = URI.parse(ATTACHE_UPLOAD_URL)
        uri.query = { file: (readable.try(:original_filename) || 'noname'), **attache_auth_options }.collect {|k,v|
          CGI.escape(k.to_s) + "=" + CGI.escape(v.to_s)
        }.join('&')
        HTTPClient.post(uri, readable, {'Content-Type' => 'binary/octet-stream'}).body
      end

      def attache_url_for(json_string, geometry)
        JSON.parse(json_string).tap do |attrs|
          prefix, basename = File.split(attrs['path'])
          attrs['url'] = [ATTACHE_DOWNLOAD_URL, prefix, CGI.escape(geometry), basename].join('/')
        end
      end

      def attache_auth_options
        if ENV['ATTACHE_SECRET_KEY']
          uuid = SecureRandom.uuid
          expiration = (Time.now + ATTACHE_UPLOAD_DURATION).to_i
          hmac = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), ENV['ATTACHE_SECRET_KEY'], "#{uuid}#{expiration}")
          { uuid: uuid, expiration: expiration, hmac: hmac }
        else
          {}
        end
      end

      def attache_options(geometry, current_value, options)
        {
          multiple: options[:multiple],
          class: 'enable-attache',
          data: {
            geometry: geometry,
            value: [*current_value],
            placeholder: [*options[:placeholder]],
            uploadurl: ATTACHE_UPLOAD_URL,
            downloadurl: ATTACHE_DOWNLOAD_URL,
          }.merge(options[:data_attrs] || {}).merge(attache_auth_options),
        }
      end
    end
  end
  module Model
    def self.included(base)
      base.extend ClassMethods
      base.class_eval do
        attr_accessor :attaches_discarded
        after_commit  :attaches_discard!, if: :attaches_discarded
      end
    end

    def attaches_discard!(files = attaches_discarded)
      if files.present?
        logger.info "DELETE #{files.inspect}"
        HTTPClient.post_content(
          URI.parse(ATTACHE_DELETE_URL),
          Utils.attache_auth_options.merge(paths: files.join("\n"))
        )
      end
    end

    module ClassMethods
      def has_one_attache(name)
        serialize name, JSON
        define_method "#{name}_options",    -> (geometry, options = {}) { Utils.attache_options(geometry, [self.send("#{name}_attributes", geometry)], multiple: false, **options) }
        define_method "#{name}_url",        -> (geometry) {               self.send("#{name}_attributes", geometry).try(:[], 'url') }
        define_method "#{name}_attributes", -> (geometry) {               str = self.send(name); Utils.attache_url_for(str, geometry) if str; }
        define_method "#{name}=",           -> (value)    {
          new_value = (value.respond_to?(:read) ? Utils.attache_upload_and_get_json(value) : value)
          old_value = self.send("#{name}_was")
          obsoleted = [*old_value].collect {|x| JSON.parse(x)['path'] } - [*new_value].collect {|x| JSON.parse(x)['path'] }
          self.attaches_discarded ||= []
          self.attaches_discarded.push(*obsoleted)
          super(new_value)
        }
        define_method "#{name}_discard",    -> do
          self.attaches_discarded ||= []
          self.attaches_discarded.push(self.send("#{name}_attributes", 'original')['path'])
        end
        after_destroy "#{name}_discard"
      end

      def has_many_attaches(name)
        serialize name, JSON
        define_method "#{name}_options",    -> (geometry, options = {}) { Utils.attache_options(geometry, self.send("#{name}_attributes", geometry), multiple: true, **options) }
        define_method "#{name}_urls",       -> (geometry) {               self.send("#{name}_attributes", geometry).collect {|attrs| attrs['url'] } }
        define_method "#{name}_attributes", -> (geometry) {
          (self.send(name) || []).inject([]) do |sum, str|
            sum + (str.blank? ? [] : [Utils.attache_url_for(str, geometry)])
          end
        }
        define_method "#{name}=",           -> (array)    {
          new_value = ((array || []).reject(&:blank?).collect {|value| value.respond_to?(:read) ? Utils.attache_upload_and_get_json(value) : value })
          old_value = [*self.send("#{name}_was")]
          obsoleted = old_value.collect {|x| JSON.parse(x)['path'] } - new_value.collect {|x| JSON.parse(x)['path'] }
          self.attaches_discarded ||= []
          self.attaches_discarded.push(*obsoleted)
          super(new_value)
        }
        define_method "#{name}_discard",    -> do
          self.attaches_discarded ||= []
          self.send("#{name}_attributes", 'original').each {|attrs| self.attaches_discarded.push(attrs['path']) }
        end
        after_destroy "#{name}_discard"
      end
    end
  end
end

ActiveRecord::Base.send(:include, AttacheRails::Model)