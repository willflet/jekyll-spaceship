# frozen_string_literal: true

require 'nokogiri'
require __dir__ + '/type'

module Jekyll::Spaceship
  class Manager
    @@_hooks = {}
    @@_processers = []

    def self.add(processor)
      # register for listening event
      processor.registers.each do |_register|
        container = _register.first
        events = _register.last.uniq
        events = events.select do |event|
          next true if event.match(/^post/)
          next !events.any?(event.to_s.gsub(/^pre/, 'post').to_sym)
        end
        events.each do |event|
          self.hook container, event
        end
      end
      @@_processers.push(processor)
      @@_processers = @@_processers.sort { |a, b| b.priority <=> a.priority }
    end

    def self.hook(container, event, &block)
      return if not is_hooked? container, event

      handler = ->(page) {
        self.dispatch page, container, event
        block.call if block
      }

      if event.to_s.start_with?('after')
        Jekyll::Hooks.register container, event do |page|
          handler.call page
        end
      elsif event.to_s.start_with?('post')
        Jekyll::Hooks.register container, event do |page|
          handler.call page
        end
        # auto add pre-event
        self.hook container, event.to_s.sub('post', 'pre').to_sym
      elsif event.to_s.start_with?('pre')
        Jekyll::Hooks.register container, event do |page|
          handler.call page
        end
      end
    end

    def self.is_hooked?(container, event)
      hook_name = "#{container}_#{event}".to_sym
      return false if @@_hooks.has_key? hook_name
      @@_hooks[hook_name] = true
    end

    def self.dispatch(page, container, event)
      @@_processers.each do |processor|
        processor.dispatch page, container, event
      end
      if event.to_s.start_with?('post') and Type.html? output_ext(page)
        self.dispatch_html_block(page)
      end
      @@_processers.each do |processor|
        processor.on_handled if processor.handled
      end
    end

    def self.ext(page)
      page.data['ext']
    end

    def self.output_ext(page)
      page.url_placeholders[:output_ext]
    end

    def self.converter(page, name)
      page.site.converters.each do |converter|
        class_name = converter.class.to_s.downcase
        return converter if class_name.end_with?(name.downcase)
      end
    end

    def self.dispatch_html_block(page)
      doc = Nokogiri::HTML(page.output)
      doc.css('script').each do |node|
        type = Type.html_block_type node['type']
        content = node.content
        next if type.nil?

        # dispatch to on_handle_html_block
        @@_processers.each do |processor|
          next unless processor.process?
          content = processor.on_handle_html_block content, type
          # dispatch to type handlers
          method = "on_handle_#{type}"
          next unless processor.respond_to? method
          content = processor.pre_exclude content
          content = processor.send method, content
          content = processor.after_exclude content
        end

        cvter = self.converter page, type
        content = cvter.convert content unless cvter.nil?

        # dispatch to on_handle_html
        @@_processers.each do |processor|
          next unless processor.process?
          content = processor.on_handle_html content
        end
        node.replace Nokogiri::HTML.fragment content
      end
      page.output = doc.to_html
    end
  end
end
