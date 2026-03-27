import Foundation

import ProjectSwitcherAppKit
import ProjectSwitcherCLICore
import ProjectSwitcherCore

let args = Array(CommandLine.arguments.dropFirst())
let cli = PsCLI(
    parser: PsArgumentParser(),
    dependencies: PsCLIDependencies(
        version: { ProjectSwitcher.version },
        projectManagerFactory: {
            ProjectManager(
                windowPositioner: AXWindowPositioner(),
                screenModeDetector: ScreenModeDetector()
            )
        },
        doctorRunner: {
            Doctor(
                runningApplicationChecker: AppKitRunningApplicationChecker(),
                windowPositioner: AXWindowPositioner()
            ).run()
        }
    ),
    output: .standard
)
exit(cli.run(arguments: args))
