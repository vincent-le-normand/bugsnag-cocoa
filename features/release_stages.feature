Feature: Discarding reports based on release stage

    Scenario: Crash when release stage is not present in "notify release stages"
        When I run "CrashWhenReleaseStageNotInNotifyReleaseStages" and relaunch the app
        And I configure Bugsnag for "CrashWhenReleaseStageNotInNotifyReleaseStages"
        And I wait for 5 seconds
        Then I should receive no requests

    Scenario: Crash when release stage is present in "notify release stages"
        When I run "CrashWhenReleaseStageInNotifyReleaseStages" and relaunch the app
        And I configure Bugsnag for "CrashWhenReleaseStageInNotifyReleaseStages"
        And I wait to receive a request
        Then the request is valid for the error reporting API version "4.0" for the "iOS Bugsnag Notifier" notifier
        And the exception "errorClass" equals "SIGABRT"
        And the event "unhandled" is true
        And the event "app.releaseStage" equals "prod"

    Scenario: Crash when release stage is changed to not present in "notify release stages" before the event
        If the current run has a different release stage than the crashing context,
        the report should only be sent if the release stage was in "notify release stages"
        at the time of the crash. Release stages can change for a single build of an app
        if the app is used as a test harness or if the build can receive code updates,
        such as JavaScript execution contexts.

        When I run "CrashWhenReleaseStageNotInNotifyReleaseStagesChanges" and relaunch the app
        And I configure Bugsnag for "CrashWhenReleaseStageNotInNotifyReleaseStagesChanges"
        And I wait for 5 seconds
        Then I should receive no requests

    Scenario: Crash when release stage is changed to be present in "notify release stages" before the event
        When I run "CrashWhenReleaseStageInNotifyReleaseStagesChanges" and relaunch the app
        And I configure Bugsnag for "CrashWhenReleaseStageInNotifyReleaseStagesChanges"
        And I wait to receive a request
        Then the request is valid for the error reporting API version "4.0" for the "iOS Bugsnag Notifier" notifier
        And the exception "errorClass" equals "SIGABRT"
        And the event "unhandled" is true
        And the event "app.releaseStage" equals "prod"

    Scenario: Notify when release stage is not present in "notify release stages"
        When I run "NotifyWhenReleaseStageNotInNotifyReleaseStages"
        And I configure Bugsnag for "NotifyWhenReleaseStageNotInNotifyReleaseStages"
        And I wait for 5 seconds
        Then I should receive no requests

    Scenario: Notify when release stage is present in "notify release stages"
        When I run "NotifyWhenReleaseStageInNotifyReleaseStages"
        And I wait to receive a request
        Then the request is valid for the error reporting API version "4.0" for the "iOS Bugsnag Notifier" notifier
        And the exception "errorClass" equals "iOSTestApp.MagicError"
        And the exception "message" equals "incoming!"
        And the event "unhandled" is false
        And the event "app.releaseStage" equals "prod"
