import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_bn.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('bn'),
    Locale('en'),
  ];

  /// Settings/About screen title
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// Button to add a new text overlay
  ///
  /// In en, this message translates to:
  /// **'Add text'**
  String get addText;

  /// App name shown in the app bar and launcher
  ///
  /// In en, this message translates to:
  /// **'Whipcut'**
  String get appName;

  /// Label for the video aspect ratio setting
  ///
  /// In en, this message translates to:
  /// **'Aspect ratio'**
  String get aspectRatio;

  /// Audio tab (music, voice-over)
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get audio;

  /// Export bitrate label (e.g. Mbps)
  ///
  /// In en, this message translates to:
  /// **'Bitrate'**
  String get bitrate;

  /// Bold toggle for text overlays
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get bold;

  /// Bottom position preset
  ///
  /// In en, this message translates to:
  /// **'Bottom'**
  String get bottom;

  /// Generic cancel action
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Center position preset
  ///
  /// In en, this message translates to:
  /// **'Center'**
  String get center;

  /// Manual update check action
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get checkForUpdates;

  /// Progress label while checking for updates
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get checkingForUpdates;

  /// Export video codec label
  ///
  /// In en, this message translates to:
  /// **'Codec'**
  String get codec;

  /// Color adjustment tab
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get color;

  /// Delete confirmation prompt for a project
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this project?'**
  String get confirmDelete;

  /// Contrast slider label (0 to 2)
  ///
  /// In en, this message translates to:
  /// **'Contrast'**
  String get contrast;

  /// Empty-state prompt to create the first project
  ///
  /// In en, this message translates to:
  /// **'Create a new project'**
  String get createNewProject;

  /// Confirm action in the new-project dialog
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get createProject;

  /// Custom export settings section
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get custom;

  /// Generic delete action
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Title of the delete-project confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete project'**
  String get deleteProject;

  /// Generic done/confirm action
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Error when the update APK download fails
  ///
  /// In en, this message translates to:
  /// **'Download failed. Please try again.'**
  String get downloadFailed;

  /// Title of the update download progress dialog
  ///
  /// In en, this message translates to:
  /// **'Downloading update…'**
  String get downloadingUpdate;

  /// Clip or project duration label
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get duration;

  /// Title of the video editor screen
  ///
  /// In en, this message translates to:
  /// **'Editor'**
  String get editor;

  /// Export / render button
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// Message shown when a render finishes
  ///
  /// In en, this message translates to:
  /// **'Export complete'**
  String get exportComplete;

  /// Title shown when a render fails
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get exportFailed;

  /// Hint shown after a successful export
  ///
  /// In en, this message translates to:
  /// **'Open it from your Files app or share it with the share sheet.'**
  String get exportHint;

  /// Section header for export quality presets
  ///
  /// In en, this message translates to:
  /// **'Export preset'**
  String get exportPreset;

  /// Progress label while a render is running
  ///
  /// In en, this message translates to:
  /// **'Exporting…'**
  String get exporting;

  /// Exposure slider label (-2 to +2 EV)
  ///
  /// In en, this message translates to:
  /// **'Exposure'**
  String get exposure;

  /// Audio fade-in label
  ///
  /// In en, this message translates to:
  /// **'Fade in'**
  String get fadeIn;

  /// Audio fade-out label
  ///
  /// In en, this message translates to:
  /// **'Fade out'**
  String get fadeOut;

  /// Label for the font size slider
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get fontSize;

  /// Frames-per-second export setting
  ///
  /// In en, this message translates to:
  /// **'FPS'**
  String get fps;

  /// H.264 codec option
  ///
  /// In en, this message translates to:
  /// **'H.264'**
  String get h264;

  /// H.265 codec option
  ///
  /// In en, this message translates to:
  /// **'H.265'**
  String get h265;

  /// Settings row opening the user guide
  ///
  /// In en, this message translates to:
  /// **'How to use'**
  String get howToUse;

  /// Button to import a .cube LUT file
  ///
  /// In en, this message translates to:
  /// **'Import .cube'**
  String get importLut;

  /// Button to pick videos/photos from the device
  ///
  /// In en, this message translates to:
  /// **'Import media'**
  String get importMedia;

  /// Button to import music from the device
  ///
  /// In en, this message translates to:
  /// **'Import music'**
  String get importMusic;

  /// Button to import a video into the timeline
  ///
  /// In en, this message translates to:
  /// **'Import video'**
  String get importVideo;

  /// App language setting
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// Snooze the update prompt until tomorrow
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// Section header for LUT (.cube) presets
  ///
  /// In en, this message translates to:
  /// **'LUT'**
  String get lut;

  /// Note that LUT rendering happens at export
  ///
  /// In en, this message translates to:
  /// **'LUTs are applied at export via ffmpeg lut3d.'**
  String get lutExportNote;

  /// Section header for the user's saved projects
  ///
  /// In en, this message translates to:
  /// **'My Projects'**
  String get myProjects;

  /// Button to start a new video project
  ///
  /// In en, this message translates to:
  /// **'New Project'**
  String get newProject;

  /// Title of the update prompt dialog
  ///
  /// In en, this message translates to:
  /// **'New version available'**
  String get newVersionAvailable;

  /// Onboarding: advance to the next page
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// Empty state: no audio clips
  ///
  /// In en, this message translates to:
  /// **'No audio tracks yet'**
  String get noAudioTracks;

  /// Empty state when there is nothing to export
  ///
  /// In en, this message translates to:
  /// **'Add video clips to the timeline before exporting.'**
  String get noClips;

  /// No LUT applied
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get noLut;

  /// Empty-state message when the user has no saved projects
  ///
  /// In en, this message translates to:
  /// **'No projects yet'**
  String get noProjects;

  /// Empty state: no text overlays
  ///
  /// In en, this message translates to:
  /// **'No text overlays yet'**
  String get noTextOverlays;

  /// Onboarding page 4 body
  ///
  /// In en, this message translates to:
  /// **'Adjust exposure, contrast, saturation and temperature — or import your own .cube LUTs.'**
  String get onbColorDesc;

  /// Onboarding page 4 title
  ///
  /// In en, this message translates to:
  /// **'Grade like a pro'**
  String get onbColorTitle;

  /// Onboarding page 5 body
  ///
  /// In en, this message translates to:
  /// **'Choose a preset or go custom — resolution, FPS, bitrate, H.264/H.265 — and save to your gallery.'**
  String get onbExportDesc;

  /// Onboarding page 5 title
  ///
  /// In en, this message translates to:
  /// **'Export in 4K'**
  String get onbExportTitle;

  /// Onboarding: finish and enter the app
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get onbGetStarted;

  /// Onboarding page 2 body
  ///
  /// In en, this message translates to:
  /// **'Tap + to create a project, pick an aspect ratio (16:9, 9:16, 1:1, 4:5), then import videos from your gallery.'**
  String get onbProjectDesc;

  /// Onboarding page 2 title
  ///
  /// In en, this message translates to:
  /// **'Start a new project'**
  String get onbProjectTitle;

  /// Onboarding: skip the intro
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onbSkip;

  /// Onboarding page 3 body
  ///
  /// In en, this message translates to:
  /// **'Tap a clip to trim or split it, change speed, reverse it — and undo anytime.'**
  String get onbTimelineDesc;

  /// Onboarding page 3 title
  ///
  /// In en, this message translates to:
  /// **'Edit on the timeline'**
  String get onbTimelineTitle;

  /// Onboarding page 1 body
  ///
  /// In en, this message translates to:
  /// **'A free, offline pro video editor for cinematographers and content creators. No subscription, no watermark.'**
  String get onbWelcomeDesc;

  /// Onboarding page 1 title
  ///
  /// In en, this message translates to:
  /// **'Welcome to Whipcut'**
  String get onbWelcomeTitle;

  /// Action to open a project in the editor
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get openProject;

  /// Keep the source resolution
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get original;

  /// Pause preview
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// Play preview
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// Label for the text overlay position presets
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get position;

  /// Caption noting filters render at export time
  ///
  /// In en, this message translates to:
  /// **'Preview applies on export'**
  String get previewOnExport;

  /// Label for the project name field in the new-project dialog
  ///
  /// In en, this message translates to:
  /// **'Project name'**
  String get projectName;

  /// Title of the projects list screen
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get projects;

  /// Export quality label
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get quality;

  /// Button to record a voice-over
  ///
  /// In en, this message translates to:
  /// **'Record voiceover'**
  String get recordVoiceover;

  /// Message when microphone permission is denied
  ///
  /// In en, this message translates to:
  /// **'Microphone permission denied'**
  String get recordingPermissionDenied;

  /// Redo last undone edit
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// Export preset name
  ///
  /// In en, this message translates to:
  /// **'Reels / TikTok'**
  String get reels;

  /// Reset color adjustments to defaults
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// Export resolution label (e.g. 1080p)
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get resolution;

  /// Reverse the selected clip's playback direction
  ///
  /// In en, this message translates to:
  /// **'Reverse'**
  String get reverse;

  /// Saturation slider label (0 to 2)
  ///
  /// In en, this message translates to:
  /// **'Saturation'**
  String get saturation;

  /// Generic save action
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Message showing where the exported file was saved
  ///
  /// In en, this message translates to:
  /// **'Saved to {path}'**
  String savedTo(Object path);

  /// Hint shown when an edit action needs a selected clip
  ///
  /// In en, this message translates to:
  /// **'Select a clip first'**
  String get selectClip;

  /// Settings screen title
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Toggle snapping the playhead to clip edges
  ///
  /// In en, this message translates to:
  /// **'Snap'**
  String get snap;

  /// Playback speed selector for a timeline clip
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get speed;

  /// Split action for a timeline clip
  ///
  /// In en, this message translates to:
  /// **'Split'**
  String get split;

  /// Button that begins rendering
  ///
  /// In en, this message translates to:
  /// **'Start export'**
  String get startExport;

  /// Button to start voice-over recording
  ///
  /// In en, this message translates to:
  /// **'Start recording'**
  String get startRecording;

  /// Button to stop voice-over recording
  ///
  /// In en, this message translates to:
  /// **'Stop recording'**
  String get stopRecording;

  /// White-balance temperature slider label (-1 to +1)
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get temperature;

  /// Text overlay tab
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get text;

  /// Label for the text color swatches
  ///
  /// In en, this message translates to:
  /// **'Text color'**
  String get textColor;

  /// Label for the text overlay content field
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get textContent;

  /// Label for the clip timeline strip
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get timeline;

  /// Guide tip: autosave
  ///
  /// In en, this message translates to:
  /// **'Autosave is on — drafts are saved automatically.'**
  String get tipAutosave;

  /// Guide tip: no watermark
  ///
  /// In en, this message translates to:
  /// **'No watermark, ever — your exports are clean.'**
  String get tipNoWatermark;

  /// Guide tip: offline
  ///
  /// In en, this message translates to:
  /// **'Works fully offline — no internet needed.'**
  String get tipOffline;

  /// Guide tips section header
  ///
  /// In en, this message translates to:
  /// **'Tips'**
  String get tipsTitle;

  /// Top position preset
  ///
  /// In en, this message translates to:
  /// **'Top'**
  String get top;

  /// Trim action for a timeline clip
  ///
  /// In en, this message translates to:
  /// **'Trim'**
  String get trim;

  /// Trim range end label
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get trimEnd;

  /// Trim range start label
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get trimStart;

  /// Undo last edit
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// Message when no update is available
  ///
  /// In en, this message translates to:
  /// **'You\'re up to date'**
  String get upToDate;

  /// Confirm action: download and install the update
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// Body of the update prompt dialog
  ///
  /// In en, this message translates to:
  /// **'Whipcut {version} is ready to install.'**
  String updateAvailableMessage(Object version);

  /// Audio volume label
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get volume;

  /// Release-notes section header in the update dialog
  ///
  /// In en, this message translates to:
  /// **'What\'s new'**
  String get whatsNew;

  /// Export preset name
  ///
  /// In en, this message translates to:
  /// **'YouTube 4K'**
  String get youtube4k;

  /// Timeline zoom level
  ///
  /// In en, this message translates to:
  /// **'Zoom'**
  String get zoom;

  /// Message when the update check itself fails (offline, timeout)
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check for updates. Check your internet connection and try again.'**
  String get updateCheckFailed;

  /// Message when copying an imported video into app storage fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t import that video. Please try another one.'**
  String get importFailed;

  /// Message when a picked video can't be opened for preview
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read that video file.'**
  String get videoUnreadable;

  /// Message when the editor preview player fails to load a clip
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the preview.'**
  String get previewLoadFailed;

  /// Generic retry action
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['bn', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bn':
      return AppLocalizationsBn();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
