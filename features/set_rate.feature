Feature: Updating Hourly Rates

  Background:
    Given there is a standard cost control project named "project1"
    And I am already logged in as "admin"

  @javascript
  Scenario: The project member has a hourly rate valid from today
    Given there is an hourly rate with the following:
      | project     | project1            |
      | user        | admin               |
      | valid_from  | Date.today          |
      | rate        | 20                  |
    When I go to the members tab of the settings page of the project "project1"
     And I set the hourly rate of user "admin" to "30"
     And I go to the hourly rates page of user "admin" of the project called "project1"
    Then I should see 1 hourly rate

  @javascript
  Scenario: The project member does not have a hourly rate valid from today
    Given there is an hourly rate with the following:
      | project     | project1            |
      | user        | admin               |
      | valid_from  | Date.today - 1      |
      | rate        | 20                  |
    When I go to the members tab of the settings page of the project "project1"
     And I set the hourly rate of user "admin" to "30"
     And I go to the hourly rates page of user "admin" of the project called "project1"
     Then I should see 2 hourly rates
