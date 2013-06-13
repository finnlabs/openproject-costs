FactoryGirl.define do
  factory :hourly_rate do
    association :user, :factory => :user
    association :project, :factory => :project
    valid_from Date.today
    rate 50.0
  end
end
