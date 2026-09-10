// PostHog product analytics for usenazar.com.
// The project token is PostHog's publishable client key.
const PROJECT_TOKEN = 'phc_BSZYpDr8ti5PJYodLmmzTTM8HjF8vHf43Xhc9QnbqFHN';
const API_HOST = 'https://z.usenazar.com';
const UI_HOST = 'https://us.posthog.com';

(function () {
  const posthog = (window.posthog = window.posthog || []);
  if (posthog.__SV) return;

  posthog._i = [];
  posthog.init = function (token, config, name) {
    const script = document.createElement('script');
    script.async = true;
    script.crossOrigin = 'anonymous';
    script.src = `${config.api_host.replace('.i.posthog.com', '-assets.i.posthog.com')}/static/array.js`;
    document.head.appendChild(script);

    let instance = posthog;
    if (name) instance = posthog[name] = [];
    else name = 'posthog';
    instance.people = instance.people || [];
    instance.toString = function (detail) {
      let label = 'posthog';
      if (name !== 'posthog') label += `.${name}`;
      return detail ? label : `${label} (stub)`;
    };
    instance.people.toString = function () { return `${instance.toString(true)}.people (stub)`; };

    const methods = 'init capture register register_once register_for_session unregister unregister_for_session getFeatureFlag getFeatureFlagResult isFeatureEnabled reloadFeatureFlags updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures on onFeatureFlags onSessionId getSurveys getActiveMatchingSurveys renderSurvey canRenderSurvey getNextSurveyStep identify setPersonProperties group resetGroups setPersonPropertiesForFlags resetPersonPropertiesForFlags setGroupPropertiesForFlags resetGroupPropertiesForFlags reset get_distinct_id getGroups get_session_id get_session_replay_url alias set_config startSessionRecording stopSessionRecording sessionRecordingStarted captureException loadToolbar get_property getSessionProperty createPersonProfile opt_in_capturing opt_out_capturing has_opted_in_capturing has_opted_out_capturing clear_opt_in_out_capturing debug'.split(' ');
    methods.forEach((method) => {
      instance[method] = function () {
        instance.push([method].concat(Array.prototype.slice.call(arguments)));
      };
    });
    posthog._i.push([token, config, name]);
  };
  posthog.__SV = 1;

  posthog.init(PROJECT_TOKEN, {
    api_host: API_HOST,
    ui_host: UI_HOST,
    defaults: '2026-05-30',
    capture_exceptions: {
      capture_unhandled_errors: true,
      capture_unhandled_rejections: true,
      capture_console_errors: false,
    },
  });
})();
