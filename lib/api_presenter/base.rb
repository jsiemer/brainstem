require 'date'
require 'api_presenter/helper'

module ApiPresenter
  class Base

    TIME_CLASSES = [Time]
    begin
      require 'active_support/time_with_zone'
      TIME_CLASSES << ActiveSupport::TimeWithZone
    rescue LoadError
    end

    class AssociationField
      attr_reader :method_name

      def initialize(method_name = nil, &block)
        if block_given?
          @block = block
        elsif method_name
          @method_name = method_name
        else
          raise ArgumentError, "Method name or block is required"
        end
      end

      def call(model)
        @block ? @block.call : model.send(@method_name)
      end
    end

    class OptionalFieldLambda < Proc; end

    class << self
      def presenters
        @presenters ||= {}
      end

      def inherited(subclass)
        names = subclass.to_s.split("::")
        namespace = names[-2] ? names[-2].downcase : "root"
        model_name = names[-1].match(/(.*?)Presenter/) && $1

        unless model_name
          raise "Presenter class names must end in Presenter, i.e. '#{name}Presenter'"
        end

        presenters[namespace] ||= {}
        presenters[namespace][model_name] = subclass.new
      end

      def default_sort_order(sort_string = nil)
        if sort_string
          @default_sort_order = sort_string
        else
          @default_sort_order
        end
      end

      def allowed_includes(includes = nil)
        if includes
          @includes = includes
        else
          @includes
        end
      end

      def sort_order(name, order = nil, &block)
        @sort_orders ||= {}
        @sort_orders[name] = (block_given? ? block : order)
      end

      def sort_orders
        @sort_orders
      end

      def filter(name, options = {}, &block)
        @filters ||= {}
        @filters[name] = [options, block]
      end

      def filters
        @filters
      end

      def namespace
        @namespace ||= begin
          presenters.keys.find{|n| presenters[n].values.any?{|p| p.class == self }}
        end
      end

      def helper
        @helper ||= ApiPresenter::Helper.for(namespace)
      end

      def respond_to?(meth)
        (helper && helper.respond_to?(meth)) || super(meth)
      end

      def method_missing(meth, *args, &block)
        if helper && helper.respond_to?(meth)
          helper.send(meth, *args, &block)
        else
          super(meth, *args, &block)
        end
      end
    end

    def default_sort_order
      self.class.default_sort_order
    end

    def allowed_includes
      self.class.allowed_includes
    end

    def sort_orders
      self.class.sort_orders
    end

    def filters
      self.class.filters
    end

    def respond_to?(meth)
      (self.class.helper && self.class.helper.respond_to?(meth)) || super(meth)
    end

    def method_missing(meth, *args, &block)
      helper = self.class.helper
      if helper && helper.respond_to?(meth)
        helper.send(meth, *args, &block)
      else
        super(meth, *args, &block)
      end
    end

    def present(model)
      raise "Please override #present(model) in your subclass of ApiPresenter::Base"
    end

    def present_and_post_process(model, fields = [], associations = [])
      post_process(present(model), model, fields, associations)
    end

    def post_process(struct, model, fields = [], associations = [])
      load_associations!(model, struct, associations)
      load_optional_fields!(struct, fields)
      struct = dates_to_strings(struct)
      datetimes_to_epoch(struct)
    end

    def group_present(models, fields = [], associations = [])
      custom_preload models, fields, associations

      models.map do |model|
        present_and_post_process model, fields, associations
      end
    end

    def custom_preload(models, fields = [], associations = [])
      # Subclasses can overload this if they wish.
    end

    def datetimes_to_epoch(struct)
      case struct
      when Array
        struct.map { |value| datetimes_to_epoch value }
      when Hash
        struct.inject({}) { |memo, (k, v)| memo[k] = datetimes_to_epoch v; memo }
      when *TIME_CLASSES # Time, ActiveSupport::TimeWithZone
        struct.to_i
      else
        struct
      end
    end

    def dates_to_strings(struct)
      case struct
        when Array
          struct.map { |value| dates_to_strings value }
        when Hash
          struct.inject({}) { |memo, (k, v)| memo[k] = dates_to_strings v; memo }
        when Date
          struct.strftime('%F')
        else
          struct
      end
    end

    def load_optional_fields!(struct, fields)
      struct.to_a.each do |key, value|
        if value.is_a?(OptionalFieldLambda)
          if fields.include?(key)
            struct[key] = value.call
          else
            struct.delete key
          end
        end
      end
    end

    def load_associations!(model, struct, associations)
      struct.to_a.each do |key, value|
        if value.is_a?(AssociationField)
          struct.delete key
          id_attr = value.method_name ? "#{value.method_name}_id" : nil
          if id_attr && model.class.columns_hash.has_key?(id_attr)
            struct["#{key}_id".to_sym] = model.send(id_attr)
          elsif associations.include?(key)
            result = value.call(model)
            if result.is_a?(Array)
              struct["#{key.to_s.singularize}_ids".to_sym] = result.map {|a| a.is_a?(ActiveRecord::Base) ? a.id : a }
            else
              if result.is_a?(ActiveRecord::Base)
                struct["#{key.to_s.singularize}_id".to_sym] = result.id
              else
                struct["#{key.to_s.singularize}_id".to_sym] = result
              end
            end
          end
        end
      end
    end

    def association(method_name = nil, &block)
      AssociationField.new method_name, &block
    end

    def optional_field(&block)
      # Don't use this because the front end does not support it yet - AC
      OptionalFieldLambda.new &block
    end
  end
end