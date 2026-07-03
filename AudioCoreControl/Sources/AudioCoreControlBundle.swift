import SwiftUI
import WidgetKit

@main
struct AudioCoreControlBundle: WidgetBundle {
    var body: some Widget {
        MuteControl()
        VolumeUpControl()
        VolumeDownControl()
    }
}
