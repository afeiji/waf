#encoding:utf-8

import os
import redis
import datetime

import re
import requests
from io import StringIO
from bs4 import BeautifulSoup
from pdfminer.layout import LAParams
from pdfminer.converter import TextConverter
from pdfminer.pdfinterp import PDFResourceManager, process_pdf


cmd_path = os.path.split(os.path.realpath(__file__))[0]
cmd_path_spider = cmd_path + "/remove_spider.txt"

r = redis.Redis(host='192.168.2.21', port=6379, db=1, password='123456')
now_time = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
# 删除不是搜狗蜘蛛ip
def remove_not_sogou_ip():
	f = open(cmd_path_spider, "at")
	read_sogou_ip = r.smembers("whitelist_sogou")
	for ip in read_sogou_ip:
		ip = ip.decode(encoding='utf-8')
		output = os.popen('nslookup {0}'.format(ip))
		ns_strip = [ns.strip()  for ns in output.readlines()]
		# 不等于-1表示这个IP是搜狗IP
		if not " ".join(ns_strip).find("sogouspider") != -1:
			r.srem("whitelist_sogou", ip)
			f.write(now_time + ": " + "sogouspider: " + ip + "\n")
	f.close()


# 删除不是百度蜘蛛ip
def remove_not_baidu_ip():
	f = open(cmd_path_spider, "at")
	read_baidu_ip = r.smembers("whitelist_baidu")
	for ip in read_baidu_ip:
		ip = ip.decode(encoding='utf-8')
		output = os.popen('nslookup {0}'.format(ip))
		ns_strip = [ns.strip()  for ns in output.readlines()]
	    # 不等于-1表示这个IP是百度IP
		if not " ".join(ns_strip).find("baiduspider") != -1:
			r.srem("whitelist_baidu", ip)
			f.write(now_time + ": " + "baiduspider: " + ip + "\n")
	f.close()


# 删除不是360蜘蛛ip


def spider1(url):
	header = {"User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 11_0 like Mac OS X) AppleWebKit/604.1.38 (KHTML, like Gecko) Version/11.0 Mobile/15A372 Safari/604.1"}
	try:	
		req = requests.get(url, headers=header)
		req.raise_for_status()
		req.encoding = 'utf-8'
		html = req.text
	except:
		print('error')
		return ''
	if not html:
  		return '这个科类啥也没找到'

	return html

def spider2(url):
	header = {"User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 11_0 like Mac OS X) AppleWebKit/604.1.38 (KHTML, like Gecko) Version/11.0 Mobile/15A372 Safari/604.1"}
	try:	
		req = requests.get(url, headers=header)
		req.raise_for_status()
		req.encoding = 'utf-8'
		html = req.content
	except:
		print('error')
		return ''
	if not html:
  		return '这个科类啥也没找到'
	return html


def parse(soup):
	print(soup.find_all("title")[0])

	for span in soup.find_all('span'):
		file_span = (span.find('a'))
		if file_span:
			file_url = file_span['href']
			print("已下载",file_url, "，文件名为：360_ips.pdf")
			file_pdf = spider2(file_url)
			if file_pdf:
				with open(cmd_path + file_name, 'wb') as f:
					f.write(file_pdf)

def read_file():
	read_360_ip = r.smembers("whitelist_360")
	list_ip = []
	f = open(cmd_path_spider,"at")
	with open(cmd_path + file_name, "rb") as my_pdf:
		rsrcmgr = PDFResourceManager()
		retstr = StringIO()
		laparams = LAParams()
		device = TextConverter(rsrcmgr, retstr, laparams=laparams)
		process_pdf(rsrcmgr, device, my_pdf)
		device.close()
		content = retstr.getvalue()
		retstr.close()
		for line in str(content).split("\n"):
			if not line:
				continue
			if '.' not in line:
				continue
			line = line.strip()
			if re.search('[a-z]', line):
				continue


			# 操作redis
			r.sadd("whitelist_360", line)
			list_ip.append(line)

		#print(list_ip)
		for ip in read_360_ip:
			ip = ip.decode(encoding='utf-8')
			if not ip in list_ip:
				r.srem("whitelist_360", ip)
				f.write(now_time + ": " + "360spider: " + ip + "\n")
		f.close()

def main_360():
	url = "https://www.so.com/help/spider_ip.html"
	html = spider1(url)
	soup = BeautifulSoup(html, 'html.parser')

	path = "spider_ip.html"
	#soup = BeautifulSoup(open(path), 'html.parser')
	parse(soup)
	read_file()



if __name__ == "__main__":
	remove_not_sogou_ip()
	remove_not_baidu_ip()

	file_name = '/360_ips.pdf'
	main_360()
