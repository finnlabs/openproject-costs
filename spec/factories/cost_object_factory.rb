FactoryGirl.define do
  factory :cost_object  do
    subject "Some Cost Object"
    description "Some costs"
    kind "VariableCostObject"
    fixed_date Date.today
    created_on 3.days.ago
    updated_on 3.days.ago
  end
end


