require 'ar_query'

class AdminAssistant
  class Index
    def initialize(
          admin_assistant, url_params = {}, conditions_from_controller = nil
        )
      @admin_assistant, @url_params, @conditions_from_controller =
            admin_assistant, url_params, conditions_from_controller
    end
    
    def belongs_to_sort_column
      columns.detect { |column|
        column.is_a?(BelongsToColumn) && column.name.to_s == sort
      }
    end
    
    def columns
      column_names = settings.column_names || model_class.columns.map(&:name)
      @admin_assistant.accumulate_columns column_names
    end
    
    def conditions_from_settings
      settings.conditions
    end
    
    def find_include
      if by_assoc = belongs_to_sort_column
        by_assoc.name
      end
    end
    
    def model_class
      @admin_assistant.model_class
    end
    
    def order_sql
      if (sc = sort_column)
        first_part = if (by_assoc = belongs_to_sort_column)
          by_assoc.order_sql_field
        else
          sc.name
        end
        "#{first_part} #{sort_order}"
      else
        settings.sort_by
      end
    end
    
    def records
      unless @records
        ar_query = ARQuery.new(
          :order => order_sql, :include => find_include,
          :per_page => 25, :page => @url_params[:page]
        )
        if @conditions_from_controller
          ar_query.condition_sqls << @conditions_from_controller
        elsif conditions_from_settings
          if conditions_from_settings.respond_to?(:call)
            conditions_sql = conditions_from_settings.call @url_params
          else
            conditions_sql = conditions_from_settings
          end
          ar_query.condition_sqls << conditions_sql if conditions_sql
        end
        search.add_to_query(ar_query)
        if settings.total_entries
          ar_query.total_entries = settings.total_entries.call
        end
        @records = model_class.paginate :all, ar_query.to_hash
      end
      @records
    end
    
    def search
      @search ||= AdminAssistant::Search.new(
        @admin_assistant, @url_params['search']
      )
    end
    
    def search_requested?
      !@url_params['search'].blank?
    end
    
    def settings
      @admin_assistant.index_settings
    end
    
    def sort
      @url_params[:sort] ||
          (settings.sort_by.to_s if settings.sort_by.is_a?(Symbol))
    end
    
    def sort_column
      if sort
        columns.detect { |c|
          c.name.to_s == sort
        } || belongs_to_sort_column
      elsif settings.sort_by.is_a?(Symbol)
        columns.detect { |c| c.name == settings.sort_by.to_s }
      end
    end
    
    def sort_order
      @url_params[:sort_order] || 'asc'
    end
    
    def view(action_view)
      @view ||= View.new(
        self, action_view, @admin_assistant
      )
    end
    
    class View
      def initialize(index, action_view, admin_assistant)
        @index, @action_view = index, action_view
        @custom_column_labels = admin_assistant.custom_column_labels
        @ajax_toggle_allowed = admin_assistant.update?
        @right_column_show = admin_assistant.show?
        @right_column_update = admin_assistant.update?
        @right_column_destroy = admin_assistant.destroy?
        @right_column_lambdas =
            admin_assistant.index_settings.right_column_links
      end
      
      def columns
        unless @columns
          @columns = @index.columns.map { |c|
            c.index_view(
              @action_view,
              :boolean_labels => @index.settings[c.name].boolean_labels,
              :sort_order => (@index.sort_order if c.name == @index.sort),
              :link_to_args => @index.settings[c.name.to_sym].link_to_args,
              :label => @custom_column_labels[c.name],
              :image_size => @index.settings[c.name.to_sym].image_size,
              :ajax_toggle_allowed => @ajax_toggle_allowed
            )
          }
        end
        @columns
      end
      
      def right_column?
        @right_column_update or
            @right_column_destroy or
            @right_column_show or
            !@right_column_lambdas.empty?
      end
      
      def right_column_links(record)
        links = ""
        if @right_column_update
          links << @action_view.link_to(
            'Edit', :action => 'edit', :id => record.id
          ) << " "
        end
        if @right_column_destroy
          links << @action_view.link_to_remote(
            'Delete',
            :url => {:action => 'destroy', :id => record.id},
            :confirm => 'Are you sure?',
            :success => "Effect.Fade('record_#{record.id}')"
          ) << ' '
        end
        if @right_column_show
          links << @action_view.link_to(
            'Show', :action => 'show', :id => record.id
          ) << ' '
        end
        @right_column_lambdas.each do |lambda|
          link_args = lambda.call record
          links << @action_view.link_to(*link_args)
        end
        links
      end
    end
  end
end
