#!/usr/bin/env ruby

# Idempotently adds the native Dauam watchOS application and its WidgetKit
# complications to the existing Flutter iOS project.

require "xcodeproj"
require "fileutils"

project_path = File.expand_path("../app/ios/Runner.xcodeproj", __dir__)
project = Xcodeproj::Project.open(project_path)

def ensure_profile_configuration(project, target)
  return if target.build_configurations.any? { |config| config.name == "Profile" }

  release = target.build_configurations.find { |config| config.name == "Release" }
  profile = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
  profile.name = "Profile"
  profile.build_settings = release.build_settings.dup
  target.build_configuration_list.build_configurations << profile
end

def configure_target(target, settings)
  target.build_configurations.each do |configuration|
    settings.each do |key, value|
      configuration.build_settings[key] = value
    end
    if configuration.name == "Debug"
      configuration.build_settings["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone"
    end
  end
end

def ensure_group(project, name, path)
  group = project.main_group.groups.find { |candidate| candidate.display_name == name }
  return group if group

  group = project.main_group.new_group(name, path)
  group
end

def ensure_file(group, path)
  group.files.find { |file| file.path == path } || group.new_file(path)
end

def ensure_copy_phase(target, name, destination)
  phase = target.copy_files_build_phases.find { |candidate| candidate.name == name }
  phase ||= target.new_copy_files_build_phase(name)
  phase.dst_path = ""
  phase.dst_subfolder_spec = destination
  phase
end

def ensure_embedded_product(phase, product_reference)
  return if phase.files_references.include?(product_reference)

  build_file = phase.add_file_reference(product_reference, true)
  build_file.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }
end

def ensure_dependency(target, dependency_target)
  return if target.dependencies.any? { |dependency| dependency.target == dependency_target }

  target.add_dependency(dependency_target)
end

runner = project.targets.find { |target| target.name == "Runner" }
abort "Runner target not found" unless runner

watch_app = project.targets.find { |target| target.name == "DauamWatchApp" }
watch_app ||= project.new_target(:application, "DauamWatchApp", :watchos, "11.0")
# Xcode 26 uses the regular application product type for SwiftUI watchOS
# applications. The legacy watchapp2 product injects a WatchKit stub binary
# and therefore conflicts with the executable produced by our Swift sources.
watch_app.product_type = "com.apple.product-type.application"

watch_widgets = project.targets.find { |target| target.name == "DauamWatchWidgets" }
watch_widgets ||= project.new_target(:app_extension, "DauamWatchWidgets", :watchos, "11.0")

ensure_profile_configuration(project, watch_app)
ensure_profile_configuration(project, watch_widgets)

common_settings = {
  "CLANG_ENABLE_MODULES" => "YES",
  "CODE_SIGN_STYLE" => "Automatic",
  "CURRENT_PROJECT_VERSION" => "1",
  "DEVELOPMENT_TEAM" => "ZV5872VU8H",
  "ENABLE_BITCODE" => "NO",
  "GENERATE_INFOPLIST_FILE" => "NO",
  "MARKETING_VERSION" => "1.0.0",
  "SDKROOT" => "watchos",
  "SUPPORTED_PLATFORMS" => "watchos watchsimulator",
  "SWIFT_VERSION" => "5.0",
  "TARGETED_DEVICE_FAMILY" => "4",
  "WATCHOS_DEPLOYMENT_TARGET" => "11.0",
}

configure_target(
  watch_app,
  common_settings.merge(
    "ASSETCATALOG_COMPILER_APPICON_NAME" => "AppIcon",
    "CODE_SIGN_ENTITLEMENTS" => "DauamWatchApp/DauamWatchApp.entitlements",
    "INFOPLIST_FILE" => "DauamWatchApp/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS" => "$(inherited) @executable_path/Frameworks",
    "PRODUCT_BUNDLE_IDENTIFIER" => "kz.dauam.watchkitapp",
    "PRODUCT_NAME" => "Dauam",
    "SKIP_INSTALL" => "YES",
  )
)

configure_target(
  watch_widgets,
  common_settings.merge(
    "APPLICATION_EXTENSION_API_ONLY" => "YES",
    "CODE_SIGN_ENTITLEMENTS" => "DauamWatchWidgets/DauamWatchWidgets.entitlements",
    "INFOPLIST_FILE" => "DauamWatchWidgets/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS" => "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks",
    "PRODUCT_BUNDLE_IDENTIFIER" => "kz.dauam.watchkitapp.DauamWatchWidgets",
    "PRODUCT_NAME" => "DauamWatchWidgets",
    "SKIP_INSTALL" => "YES",
  )
)

watch_app_group = ensure_group(project, "DauamWatchApp", "DauamWatchApp")
watch_shared_group = ensure_group(project, "DauamWatchShared", "DauamWatchShared")
watch_widgets_group = ensure_group(project, "DauamWatchWidgets", "DauamWatchWidgets")

watch_app_files = %w[
  DauamWatchApp.swift
  DauamWatchViews.swift
  WatchConnectivityReceiver.swift
].map { |path| ensure_file(watch_app_group, path) }
watch_app.add_file_references(watch_app_files)

watch_app_info = ensure_file(watch_app_group, "Info.plist")
watch_app_entitlements = ensure_file(watch_app_group, "DauamWatchApp.entitlements")
watch_assets = ensure_file(watch_app_group, "Assets.xcassets")
watch_app.resources_build_phase.add_file_reference(watch_assets, true) unless
  watch_app.resources_build_phase.files_references.include?(watch_assets)

shared_snapshot = ensure_file(watch_shared_group, "DauamWatchSnapshot.swift")
watch_app.add_file_references([shared_snapshot])
watch_widgets.add_file_references([shared_snapshot])

watch_widget_files = %w[
  DauamWatchWidgets.swift
  DauamWatchWidgetsBundle.swift
].map { |path| ensure_file(watch_widgets_group, path) }
watch_widgets.add_file_references(watch_widget_files)
ensure_file(watch_widgets_group, "Info.plist")
ensure_file(watch_widgets_group, "DauamWatchWidgets.entitlements")

runner_group = project.main_group.groups.find { |group| group.display_name == "Runner" }
abort "Runner group not found" unless runner_group
watch_sync = ensure_file(runner_group, "WatchSyncManager.swift")
runner.add_file_references([watch_sync])

watch_extensions_phase = ensure_copy_phase(watch_app, "Embed App Extensions", "13")
ensure_embedded_product(watch_extensions_phase, watch_widgets.product_reference)
ensure_dependency(watch_app, watch_widgets)

watch_content_phase = ensure_copy_phase(runner, "Embed Watch Content", "1")
# The companion belongs inside Runner.app/Watch. Products Directory (16)
# copies Dauam.app beside Runner.app and creates a cycle with Flutter's
# Thin Binary phase.
watch_content_phase.dst_path = "Watch"
ensure_embedded_product(watch_content_phase, watch_app.product_reference)
ensure_dependency(runner, watch_app)

# ProcessInfoPlistFile inspects embedded Watch content. Flutter's Thin Binary
# phase in turn touches the finished app bundle, so the Watch copy must happen
# before Thin Binary or Xcode detects a dependency cycle.
thin_binary_phase = runner.build_phases.find { |phase| phase.display_name == "Thin Binary" }
if thin_binary_phase
  runner.build_phases.delete(watch_content_phase)
  runner.build_phases.insert(runner.build_phases.index(thin_binary_phase), watch_content_phase)
end

target_attributes = project.root_object.attributes["TargetAttributes"] ||= {}
[watch_app, watch_widgets].each do |target|
  target_attributes[target.uuid] ||= {}
  target_attributes[target.uuid]["CreatedOnToolsVersion"] = "26.6"
  target_attributes[target.uuid]["DevelopmentTeam"] = "ZV5872VU8H"
  target_attributes[target.uuid]["ProvisioningStyle"] = "Automatic"
end

project.save

scheme_dir = File.join(project_path, "xcshareddata", "xcschemes")
scheme_path = File.join(scheme_dir, "#{watch_app.name}.xcscheme")
FileUtils.mkdir_p(scheme_dir)
File.write(
  scheme_path,
  <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <Scheme
       LastUpgradeVersion = "2660"
       version = "1.7">
       <BuildAction
          parallelizeBuildables = "YES"
          buildImplicitDependencies = "YES"
          buildArchitectures = "Automatic">
          <BuildActionEntries>
             <BuildActionEntry
                buildForTesting = "YES"
                buildForRunning = "YES"
                buildForProfiling = "YES"
                buildForArchiving = "YES"
                buildForAnalyzing = "YES">
                <BuildableReference
                   BuildableIdentifier = "primary"
                   BlueprintIdentifier = "#{watch_app.uuid}"
                   BuildableName = "#{watch_app.product_reference.path}"
                   BlueprintName = "#{watch_app.name}"
                   ReferencedContainer = "container:Runner.xcodeproj">
                </BuildableReference>
             </BuildActionEntry>
          </BuildActionEntries>
       </BuildAction>
       <TestAction
          buildConfiguration = "Debug"
          selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
          selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
          shouldUseLaunchSchemeArgsEnv = "YES">
       </TestAction>
       <LaunchAction
          buildConfiguration = "Debug"
          selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
          selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
          launchStyle = "0"
          useCustomWorkingDirectory = "NO"
          ignoresPersistentStateOnLaunch = "NO"
          debugDocumentVersioning = "YES"
          debugServiceExtension = "internal"
          allowLocationSimulation = "YES">
          <BuildableProductRunnable
             runnableDebuggingMode = "0">
             <BuildableReference
                BuildableIdentifier = "primary"
                BlueprintIdentifier = "#{watch_app.uuid}"
                BuildableName = "#{watch_app.product_reference.path}"
                BlueprintName = "#{watch_app.name}"
                ReferencedContainer = "container:Runner.xcodeproj">
             </BuildableReference>
          </BuildableProductRunnable>
       </LaunchAction>
       <ProfileAction
          buildConfiguration = "Release"
          shouldUseLaunchSchemeArgsEnv = "YES"
          savedToolIdentifier = ""
          useCustomWorkingDirectory = "NO"
          debugDocumentVersioning = "YES">
          <BuildableProductRunnable
             runnableDebuggingMode = "0">
             <BuildableReference
                BuildableIdentifier = "primary"
                BlueprintIdentifier = "#{watch_app.uuid}"
                BuildableName = "#{watch_app.product_reference.path}"
                BlueprintName = "#{watch_app.name}"
                ReferencedContainer = "container:Runner.xcodeproj">
             </BuildableReference>
          </BuildableProductRunnable>
       </ProfileAction>
       <AnalyzeAction buildConfiguration = "Debug">
       </AnalyzeAction>
       <ArchiveAction
          buildConfiguration = "Release"
          revealArchiveInOrganizer = "YES">
       </ArchiveAction>
    </Scheme>
  XML
)

puts "Configured #{watch_app.name} and #{watch_widgets.name}"
