require_dependency 'time_entry'

# Patches Redmine's Users dynamically.
module OpenProject::Costs::Patches::TimeEntryPatch
  def self.included(base) # :nodoc:
    base.extend(ClassMethods)

    base.send(:include, InstanceMethods)

    # Same as typing in the class t.update_costs
    base.class_eval do
      unloadable

      belongs_to :rate, :conditions => {:type => ["HourlyRate", "DefaultHourlyRate"]}, :class_name => "Rate"
      attr_protected :costs, :rate_id

      scope :visible, lambda{|*args|
        { :include => [:project, :user],
          :conditions => TimeEntry.visible_condition(args[0] || User.current, args[1])
        }
      }

      before_save :update_costs

      def self.visible_condition(user, project)
        %Q{ (#{Project.allowed_to_condition(user, :view_time_entries, :project => project)} OR
             (#{Project.allowed_to_condition(user, :view_own_time_entries, :project => project)} AND #{TimeEntry.table_name}.user_id = #{user.id})) }
      end

      scope :visible_costs, lambda{|*args|
        user = args.first || User.current
        project = args[1]

        view_hourly_rates = %Q{ (#{Project.allowed_to_condition(user, :view_hourly_rates, :project => project)} OR
                                (#{Project.allowed_to_condition(user, :view_own_hourly_rate, :project => project)} AND #{TimeEntry.table_name}.user_id = #{user.id})) }
        view_time_entries = TimeEntry.visible_condition(user, project)

        { :include => [:project, :user],
          :conditions => [view_time_entries, view_hourly_rates].join(" AND ")
        }
      }

    end

  end

  module ClassMethods
    def update_all(updates, conditions = nil, options = {})
      # instead of a update_all, perform an individual update during work_package#move
      # to trigger the update of the costs based on new rates
      if conditions.respond_to?(:keys) && conditions.keys == [:work_package_id] && updates =~ /^project_id = ([\d]+)$/
        project_id = $1
        time_entries = TimeEntry.all(:conditions => conditions)
        time_entries.each do |entry|
          entry.project_id = project_id
          entry.save!
        end
      else
        super
      end
    end
  end

  module InstanceMethods

    def real_costs
      # This methods returns the actual assigned costs of the entry
      overridden_costs || costs || calculated_costs
    end

    def calculated_costs(rate_attr = nil)
      rate_attr ||= current_rate
      hours * rate_attr.rate
    rescue
      0.0
    end

    def update_costs(rate_attr = nil)
      rate_attr ||= current_rate
      if rate_attr.nil?
        self.costs = 0.0
        self.rate = nil
        return
      end

      self.costs = calculated_costs(rate_attr)
      self.rate = rate_attr
    end

    def update_costs!(rate_attr = nil)
      self.update_costs(rate_attr)
      self.save!
    end

    def current_rate
      self.user.rate_at(self.spent_on, self.project_id)
    end

    def visible_by?(usr)
      usr.allowed_to?(:view_time_entries, project)
    end

    def costs_visible_by?(usr)
      usr.allowed_to?(:view_hourly_rates, project) ||
        (user_id == usr.id && usr.allowed_to?(:view_own_hourly_rate, project))
    end
  end
end

TimeEntry.send(:include, OpenProject::Costs::Patches::TimeEntryPatch)
