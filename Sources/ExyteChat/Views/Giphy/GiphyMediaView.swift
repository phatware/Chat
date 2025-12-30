#if GIPHY_UISDK

import GiphyUISDK
import SwiftUI

struct GiphyMediaView: UIViewRepresentable {

   let id: String
   @Binding var aspectRatio: CGFloat

   func makeUIView(context: Context) -> GPHMediaView {
       let view = GPHMediaView()
       GiphyCore.shared.gifByID(id) { (response, error) in
           if let media = response?.data {
               DispatchQueue.main.async {
                   view.setMedia(media)
                   self.aspectRatio = media.aspectRatio
               }
           }
       }
       return view
   }

   func updateUIView(_ uiView: GPHMediaView, context: Context) {
       // uiView.media = media
   }
}

#endif