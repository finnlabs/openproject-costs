class WorkPackage
  class LaborCosts < AbstractCosts
    def costs_model
      TimeEntry
    end

    def filter_authorized(scope)
      TimeEntry.with_visible_costs_on scope
    end

    def wp_table
      WorkPackage.arel_table
    end

    def costs_sum_alias
      'time_entries_sum'
    end
  end
end
