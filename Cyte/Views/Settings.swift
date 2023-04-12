//
//  Settings.swift
//  Cyte
//
//  Created by Shaun Narayan on 7/03/23.
//

import Foundation
import SwiftUI
import KeychainSwift
import AXSwift

struct BundleView: View {
    @EnvironmentObject var bundleCache: BundleCache
    
    @State var bundle: BundleExclusion
    @State var isExcluded: Bool
    
    var body: some View {
        HStack {
            let binding = Binding<Bool>(get: {
                return isExcluded
            }, set: {
                if $0 {
                    bundle.excluded = true
                    do {
                        try PersistenceController.shared.container.viewContext.save()
                        
                        let episodeFetch : NSFetchRequest<Episode> = Episode.fetchRequest()
                        episodeFetch.predicate = NSPredicate(format: "bundle == %@", bundle.bundle!)
                        let episodes: [Episode] = try PersistenceController.shared.container.viewContext.fetch(episodeFetch)
                        for episode in episodes {
                            Memory.shared.delete(delete_episode: episode)
                        }
                    } catch {
                    }
                    Task {
                        if ScreenRecorder.shared.isRunning {
                            await ScreenRecorder.shared.stop()
                            await ScreenRecorder.shared.start()
                        }
                    }
                } else {
                    bundle.excluded = false
                    do {
                        try PersistenceController.shared.container.viewContext.save()
                    } catch {
                        
                    }
                }
                isExcluded = bundle.excluded
            })
            Image(nsImage: bundleCache.getIcon(bundleID: bundle.bundle!))
                .frame(width: 32, height: 32)
            Text(getApplicationNameFromBundleID(bundleID: bundle.bundle!) ?? bundle.bundle!)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(isOn: binding) {
                
            }
        }
    }
    
}

struct Settings: View {
    @FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \BundleExclusion.bundle, ascending: true)],
            animation: .default)
    private var bundles: FetchedResults<BundleExclusion>
    @State var isShowing = false
    @State var isShowingHomeSelection = false
    @State var apiDetails: String = ""
    private let defaults = UserDefaults.standard
    @State var isHovering: Bool = false
    @State var currentRetention: Int = 0
    @State var browserAware: Bool = false
    
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text("Settings").font(.title)
                    .padding()
                
                HStack {
                    Text("Saving memories in: \(homeDirectory().path(percentEncoded: false))")
                        .font(.title2)
                        .frame(width: 1000, height: 50, alignment: .leading)
                    Button(action: {
                        isShowingHomeSelection.toggle()
                    }) {
                        Image(systemName: "folder")
                    }
                    .fileImporter(isPresented: $isShowingHomeSelection, allowedContentTypes: [.directory], onCompletion: { result in
                        switch result {
                        case .success(let Fileurl):
                            let defaults = UserDefaults.standard
                            defaults.set(Fileurl.path(percentEncoded: false), forKey: "CYTE_HOME")
                            break
                        case .failure(let error):
                            log.error(error)
                        }
                    })
                }
                .accessibilityLabel("Path currently used to store memories and a button to update it")
                .padding(EdgeInsets(top: 0.0, leading: 15.0, bottom: 5.0, trailing: 0.0))
                
                Text("Save recordings for (will use approximately 1GB for every four hours: this can vary greatly depending on amount of context switching)").font(.title2)
                    .padding()
                    .onAppear {
                        currentRetention = defaults.integer(forKey: "CYTE_RETENTION")
                    }
                
                
                HStack {
                    ForEach(Array(["Forever", "30 Days", "60 Days", "90 Days"].enumerated()), id: \.offset) { index, retain in
                        Text(retain)
                            .frame(width: 244, height: 50)
                            .background(currentRetention == (index * 30) ? Color(red: 177.0 / 255.0, green: 181.0 / 255.0, blue: 255.0 / 255.0) : .white)
                            .foregroundColor(currentRetention == (index * 30) ? .black : .gray)
                            .onHover(perform: { hovering in
                                self.isHovering = hovering
                                if hovering {
                                    NSCursor.pointingHand.set()
                                } else {
                                    NSCursor.arrow.set()
                                }
                            })
                            .onTapGesture {
                                defaults.set(index * 30, forKey: "CYTE_RETENTION")
                                currentRetention = index * 30
                            }
                    }
                }
                .padding(EdgeInsets(top: 0.0, leading: 15.0, bottom: 5.0, trailing: 0.0))
                
                VStack(alignment: .leading) {
                    Text("To enable Knowledge base features enter your GPT4 API key, or a path to a llama.cpp compatible model file").font(.title2)
                        .padding(EdgeInsets(top: 0.0, leading: 15.0, bottom: 5.0, trailing: 0.0))
                    Text("Privacy note: This feature will make requests to the OpenAI servers if you supply an API key")
                        .font(.caption)
                        .padding(EdgeInsets(top: 5.0, leading: 15.0, bottom: 5.0, trailing: 0.0))
                }
                
                HStack {
                    if Agent.shared.isSetup {
                        Text("Knowledge base enabled")
                            .frame(width: 1000, height: 50)
                            .background(Color(red: 177.0 / 255.0, green: 181.0 / 255.0, blue: 255.0 / 255.0))
                        Button(action: {
                            let keys = KeychainSwift()
                            let _ = keys.delete("CYTE_LLM_KEY")
                            Agent.shared.teardown()
                        }) {
                            Image(systemName: "multiply")
                        }
                        
                    } else {
                        TextField(
                            "OpenAI API Key or path to LLaMA model",
                            text: $apiDetails
                        )
                        .padding(EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10))
                        .textFieldStyle(.plain)
                        .background(.white)
                        .font(.title)
                        .frame(width: 1000)
                        .onSubmit {
                            Agent.shared.setup(key: apiDetails)
                            apiDetails = ""
                        }
                        Button(action: {
                            Agent.shared.setup(key: apiDetails)
                            apiDetails = ""
                        }) {
                            Image(systemName: "checkmark.message")
                        }
                    }
                }
                .padding(EdgeInsets(top: 0.0, leading: 15.0, bottom: 5.0, trailing: 0.0))
                
                HStack {
                    let binding = Binding<Bool>(get: {
                        return browserAware
                    }, set: {
                        defaults.set($0, forKey: "CYTE_BROWSER")
                        browserAware = $0
                        checkIsProcessTrusted(prompt: $0)
                    })
                    Text("Browser awareness (Ignore Incognito and Private Browsing windows, episodes track domains)")
                        .font(.title2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onAppear {
                            browserAware = defaults.bool(forKey: "CYTE_BROWSER")
                        }
                        .frame(width: 1000, height: 50, alignment: .leading)
                    Toggle(isOn: binding) {
                        
                    }
                    .accessibilityLabel("Checkbox to enable browser awareness")
                }
                .padding(EdgeInsets(top: 0.0, leading: 15.0, bottom: 0.0, trailing: 0.0))
                
                Text("Privacy note: This feature will request icons for display from https://www.google.com/s2/favicons on startup")
                    .font(.caption)
                    .padding(EdgeInsets(top: 0.0, leading: 15.0, bottom: 5.0, trailing: 0.0))
                
                VStack(alignment: .leading) {
                    HStack {
                        Text("Select applications you wish to disable recording for")
                            .font(Font.title2)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    Button(action: {
                        isShowing.toggle()
                    }) {
                        HStack {
                            Text("Add application")
                            Image(systemName: "plus")
                        }
                        .cornerRadius(10.0)
                        .foregroundColor(.gray)
                    }
                    .accessibilityLabel("Tap to add an app that should not be recorded")
                    .padding()
                    .buttonStyle(.plain)
                    .background(.white)
                    .fileImporter(isPresented: $isShowing, allowedContentTypes: [.application], onCompletion: { result in
                        switch result {
                        case .success(let Fileurl):
                            let _ = Memory.shared.getOrCreateBundleExclusion(name: (Bundle(url: Fileurl)?.bundleIdentifier)!, excluded: true)
                            break
                        case .failure(let error):
                            log.error(error)
                        }
                    })
                }
                .padding()
            
                HStack {
                    List(Array(bundles.enumerated()), id: \.offset) { index, bundle in
                        if bundle.bundle != Bundle.main.bundleIdentifier && index % 2 == 0 {
                            BundleView(bundle: bundle, isExcluded: bundle.excluded)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .frame(width: 400)
                    List(Array(bundles.enumerated()), id: \.offset) { index, bundle in
                        if bundle.bundle != Bundle.main.bundleIdentifier && index % 2 == 1 {
                            BundleView(bundle: bundle, isExcluded: bundle.excluded)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .frame(width: 400)
                }
                .accessibilityLabel("Grid of known applications and if they are to be recorded")
                .frame(height: ceil(CGFloat(bundles.count) / 2.0) * 42.0)
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Back", action: { self.presentationMode.wrappedValue.dismiss() })
                    .frame(width: 50)
            }
        }
    }
}
