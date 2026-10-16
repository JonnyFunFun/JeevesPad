export THEOS = $(HOME)/dev/theos
export ARCHS = armv7 arm64
export TARGET = iphone:clang:9.3:9.0

include $(THEOS)/makefiles/common.mk

ADDITIONAL_CFLAGS += -Wno-unknown-warning-option
ADDITIONAL_OBJCCFLAGS += -Wno-unknown-warning-option
APPLICATION_NAME = Jeeves

Jeeves_FILES = Jeeves/main.m \
	Jeeves/AppDelegate.m \
	Jeeves/Models/HAEntity.m \
	Jeeves/Models/JeevesRoom.m \
	Jeeves/Models/JeevesCardSettings.m \
	Jeeves/Models/JeevesLovelaceDashboard.m \
	Jeeves/Models/JeevesWeatherSettings.m \
	Jeeves/Models/JeevesFleetSettings.m \
	Jeeves/Models/JeevesJellyfinItem.m \
	Jeeves/Models/JeevesJellyfinTarget.m \
	Jeeves/Models/JeevesJellyfinStream.m \
	Jeeves/Models/JeevesJellyfinSession.m \
	Jeeves/API/HAAPIClient.m \
	Jeeves/API/JeevesWebSocket.m \
	Jeeves/API/HAWebSocketClient.m \
	Jeeves/API/JeevesFleetService.m \
	Jeeves/API/JeevesPhoneRegistry.m \
	Jeeves/API/JeevesBatteryReporter.m \
	Jeeves/API/JeevesJellyfinClient.m \
	Jeeves/Helpers/UIViewController+JeevesRefresh.m \
	Jeeves/Helpers/JeevesIdleManager.m \
	Jeeves/Helpers/JeevesMotionDetector.m \
	Jeeves/Helpers/JeevesFleetCrypto.m \
	Jeeves/Helpers/JeevesPhonePairer.m \
	Jeeves/Helpers/JeevesGuidedAccess.m \
	Jeeves/Helpers/JeevesMaintenance.m \
	Jeeves/Theme/JeevesThemeManager.m \
	Jeeves/Views/EntityCell.m \
	Jeeves/Views/JeevesRoomCell.m \
	Jeeves/Views/JeevesLightToggleCell.m \
	Jeeves/Views/JeevesIconView.m \
	Jeeves/Views/JeevesActionButton.m \
	Jeeves/Views/JeevesJellyfinMediaCell.m \
	Jeeves/Views/JeevesJellyfinRowView.m \
	Jeeves/Views/JeevesJellyfinNowPlayingPill.m \
	Jeeves/Views/JeevesLightControlsView.m \
	Jeeves/Views/JeevesGridLayout.m \
	Jeeves/ViewControllers/DashboardViewController.m \
	Jeeves/ViewControllers/JeevesDashboardViewController.m \
	Jeeves/ViewControllers/JeevesRoomDetailViewController.m \
	Jeeves/ViewControllers/JeevesAddRoomViewController.m \
	Jeeves/ViewControllers/CameraViewController.m \
	Jeeves/ViewControllers/SettingsViewController.m \
	Jeeves/ViewControllers/LightControlViewController.m \
	Jeeves/ViewControllers/JeevesJellyfinViewController.m \
	Jeeves/ViewControllers/JeevesJellyfinLibraryViewController.m \
	Jeeves/ViewControllers/JeevesJellyfinShowViewController.m \
	Jeeves/ViewControllers/JeevesJellyfinDetailViewController.m \
	Jeeves/ViewControllers/JeevesJellyfinSearchViewController.m \
	Jeeves/ViewControllers/JeevesJellyfinNowPlayingViewController.m \
	Jeeves/ViewControllers/JeevesLovelaceViewController.m \
	Jeeves/ViewControllers/JeevesEntityPickerViewController.m \
	Jeeves/ViewControllers/JeevesWeatherSettingsViewController.m \
	Jeeves/ViewControllers/JeevesFleetViewController.m \
	Jeeves/ViewControllers/JeevesPresenceViewController.m \
	Jeeves/ViewControllers/JeevesAddPhoneViewController.m \
	Jeeves/ViewControllers/JeevesPairPhoneViewController.m \
	Jeeves/ViewControllers/JeevesGuidedAccessViewController.m \
	Jeeves/ViewControllers/JeevesEntityMoreInfoViewController.m

Jeeves_FRAMEWORKS = UIKit Foundation CFNetwork CoreGraphics QuartzCore AVFoundation CoreMedia CoreVideo CoreBluetooth Security

Jeeves_CFLAGS = -fobjc-arc -fno-modules -fno-threadsafe-statics -Wno-deprecated-module-dot-map -Wno-nullability-completeness -Wno-nullability -IJeeves -IJeeves/API -IJeeves/Models -IJeeves/Views -IJeeves/ViewControllers -IJeeves/Theme -IJeeves/Helpers
Jeeves_USE_MODULES = 0

include $(THEOS_MAKE_PATH)/application.mk
