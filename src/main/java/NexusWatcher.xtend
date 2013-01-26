/**
 * Copyright 2013 José Martínez
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import java.awt.Desktop
import java.awt.MenuItem
import java.awt.PopupMenu
import java.awt.SystemTray
import java.awt.Toolkit
import java.awt.TrayIcon
import java.net.URI
import java.util.concurrent.TimeUnit

import com.google.common.io.Resources
import com.google.common.util.concurrent.AbstractScheduledService
import com.google.common.util.concurrent.ServiceManager

import org.eclipse.jetty.client.HttpClient
import org.eclipse.jetty.client.api.Result
import org.eclipse.jetty.client.util.BufferingResponseListener
import org.eclipse.jetty.http.HttpStatus
import org.eclipse.jetty.util.ssl.SslContextFactory

class NexusWatcher {

	static val ENTRIES = newImmutableMap(
		'Nexus 4 8GB' -> nexusUri('nexus_4_8gb'),
		'Nexus 4 16GB' -> nexusUri('nexus_4_16gb'),
		'Nexus 4 Bumper' -> nexusUri('nexus_4_bumper_black')
		//'Nexus 7 16GB' -> nexusUri('nexus_7_16gb'),
		//'Nexus 7 32GB' -> nexusUri('nexus_7_32gb'),
		//'Nexus 7 32GB HSPA+' -> nexusUri('nexus_7_32gb_hspa'),
		//'Nexus 10 16GB' -> nexusUri('nexus_10_16gb'),
		//'Nexus 10 32GB' -> nexusUri('nexus_10_32gb')
	)

	def static void main(String[] args) {
		System::setProperty('apple.awt.UIElement', 'true')

		if (!SystemTray::supported) {
			println('SystemTray is not supported')
			System::exit(1)
		}

		val watcher = new WatcherService
		val manager = new ServiceManager(newImmutableSet(watcher))

		val SOLDOUT = Toolkit::defaultToolkit.createImage(Resources::getResource('icon-soldout.png'))
		val AVAILABLE = Toolkit::defaultToolkit.createImage(Resources::getResource('icon-available.png'))

		val trayIcon = new TrayIcon(SOLDOUT)
		trayIcon.toolTip = 'Nexus availability'
		trayIcon.popupMenu = new PopupMenu => [
			ENTRIES.forEach [ name, uri |
				add(new MenuItem(name)) => [
					addActionListener [Desktop::desktop.browse(uri)]
					watcher.addHandler(uri) [ status |
						label = name + ' - ' + status
						if (status == 'AVAILABLE!') {
							trayIcon.image = AVAILABLE
							Desktop::desktop.browse(uri)
						}
					]
				]
			]
			addSeparator
			add(new MenuItem('Exit')) => [
				addActionListener [manager.stopAsync]
			]
		]

		SystemTray::systemTray.add(trayIcon)
		manager.startAsync.awaitStopped
		System::exit(0)
	}

	def private static nexusUri(String deviceName) {
		URI::create('https://play.google.com/store/devices/details?id=' + deviceName)
	}

}

class WatcherService extends AbstractScheduledService {

	val client = new HttpClient(new SslContextFactory => [validateCerts = true])
	val uris = <URI, (String)=>void>newHashMap

	def void addHandler(URI uri, (String)=>void handler) {
		uris.put(uri, handler)
	}

	override protected startUp() throws Exception {
		client.start
	}

	override protected shutDown() throws Exception {
		client.stop
	}

	override protected runOneIteration() throws Exception {
		uris.forEach [ uri, handler |
			handler.apply('CHECKING...')
			val r = client.newRequest(uri)
			try
				r.send(new ResponseListener(handler))
			catch (Throwable t) // Jetty bug
				r.abort(t)
		]
	}

	override protected scheduler() {
		AbstractScheduledService$Scheduler::newFixedRateSchedule(0, 15, TimeUnit::MINUTES)
	}

}

class ResponseListener extends BufferingResponseListener {

	(String)=>void handler

	new((String)=>void handler) {
		this.handler = handler
	}

	override onComplete(Result result) {
		handler.apply(
			switch result {
				case result.failed: 'ERROR ' + result.failure.^class.simpleName
				case result.response.status != HttpStatus::OK_200: 'HTTP ' + result.response.reason
				case contentAsString.contains('hardware-sold-out'): 'SOLD OUT'
				default: 'AVAILABLE!'
			})
	}

}
