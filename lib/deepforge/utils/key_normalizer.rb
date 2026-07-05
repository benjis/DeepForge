# frozen_string_literal: true

module DeepForge
  module Utils
    module KeyNormalizer
      module_function

      def to_snake(key)
        key.to_s.gsub('::', '/')
           .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
           .gsub(/([a-z\d])([A-Z])/, '\1_\2')
           .tr('-', '_')
           .downcase
           .to_sym
      end

      def to_camel(key)
        parts = key.to_s.split('_')
        return key if parts.length == 1

        (parts[0] + parts[1..].map(&:capitalize).join).to_sym
      end

      def transform_keys(hash, &converter)
        hash.each_with_object({}) do |(k, v), result|
          new_key = converter.call(k)
          result[new_key] = v.is_a?(Hash) ? transform_keys(v, &converter) : v
        end
      end

      def snakify_keys(hash)
        transform_keys(hash) { |k| to_snake(k) }
      end

      def camelize_keys(hash)
        transform_keys(hash) { |k| to_camel(k) }
      end
    end
  end
end
