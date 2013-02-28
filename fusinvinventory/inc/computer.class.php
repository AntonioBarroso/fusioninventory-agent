<?php

/*
   ------------------------------------------------------------------------
   FusionInventory
   Copyright (C) 2010-2012 by the FusionInventory Development Team.

   http://www.fusioninventory.org/   http://forge.fusioninventory.org/
   ------------------------------------------------------------------------

   LICENSE

   This file is part of FusionInventory project.

   FusionInventory is free software: you can redistribute it and/or modify
   it under the terms of the GNU Affero General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   FusionInventory is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
   GNU Affero General Public License for more details.

   You should have received a copy of the GNU Affero General Public License
   along with Behaviors. If not, see <http://www.gnu.org/licenses/>.

   ------------------------------------------------------------------------

   @package   FusionInventory
   @author    David Durieux
   @co-author 
   @copyright Copyright (c) 2010-2012 FusionInventory team
   @license   AGPL License 3.0 or (at your option) any later version
              http://www.gnu.org/licenses/agpl-3.0-standalone.html
   @link      http://www.fusioninventory.org/
   @link      http://forge.fusioninventory.org/projects/fusioninventory-for-glpi/
   @since     2010
 
   ------------------------------------------------------------------------
 */

if (!defined('GLPI_ROOT')) {
   die("Sorry. You can't access directly to this file");
}

class PluginFusinvinventoryComputer extends CommonDBTM {
   
   static function getTypeName() {

      return "";
   }

   function canCreate() {
      return haveRight('computer', 'w');
   }


   function canView() {
      return haveRight('computer', 'r');
   }

   
   /**
    * Display informations about computer (bios...) 
    * 
    * @global type $LANG
    * @param type $computers_id 
    */   
   function showForm($computers_id) {
      global $LANG;
      
      $a_computerextend = current($this->find("`computers_id`='".$computers_id."'", 
                                              "", 1));
      if (empty($a_computerextend)) {
         $this->getEmpty();
         $a_computerextend = $this->fields;
      }
      
      echo '<div align="center">';
      echo '<table class="tab_cadre_fixe" style="margin: 0; margin-top: 5px;">';
      echo '<tr>';
      echo '<th colspan="4">'.$LANG['entity'][14].'</th>';
      echo '</tr>';

      echo '<tr class="tab_bg_1">';
      echo '<th colspan="2" width="50%">'.$LANG['plugin_fusinvinventory']['bios'][0].'</th>';
      echo '<th colspan="2">'.$LANG['common'][67].'</th>';
      echo '</tr>';
      
      echo '<tr class="tab_bg_1">';
      echo '<td>'.$LANG['common'][27].'&nbsp;:</td>';
      echo '<td>'.convDate($a_computerextend['bios_date']).'</td>';
      echo "<td>".$LANG['computers'][9]." - ".$LANG['install'][3]." (".strtolower($LANG['common'][27]).")&nbsp;:</td>";
      echo '<td>'.convDate($a_computerextend['operatingsystem_installationdate']).'</td>';
      echo '</tr>';

      echo '<tr class="tab_bg_1">';
      echo '<td>'.$LANG['rulesengine'][78].'&nbsp;:</td>';
      echo '<td>'.$a_computerextend['bios_version'].'</td>';
      echo '<td>'.$LANG['plugin_fusinvinventory']['computer'][1].'&nbsp;:</td>';
      echo '<td>'.$a_computerextend['winowner'].'</td>';
      echo '</tr>';

      echo '<tr class="tab_bg_1">';
      echo '<td>'.$LANG['common'][5].'&nbsp;:</td>';
      echo '<td>';
      echo Dropdown::getDropdownName("glpi_manufacturers", $a_computerextend['bios_manufacturers_id']);
      echo '</td>';
      echo '<td>'.$LANG['plugin_fusinvinventory']['computer'][2].'&nbsp;:</td>';
      echo '<td>'.$a_computerextend['wincompany'].'</td>';
      echo '</tr>';
            
      echo '</table>';
      $this->showActiveCampaignRegistryKeys($computers_id);
      echo '</div>';      
   }

/**
    * Display informations about active campaign register keys
    * 
    * @global type $LANG
    * @param type $computers_id 
    */
   function showActiveCampaignRegistryKeys($computers_id) {
      global $LANG, $DB;

      $collectObject = new PluginFusioninventoryCollect();
      $sqlCollectCampaign  = "plugin_fusioninventory_collecttypes_id = 1";
      $sqlCollectCampaign .= " AND is_active = 1";
      $resultCollectCampaign = $collectObject->find($sqlCollectCampaign);

      if(count($resultCollectCampaign) === 0) return false;

      $campaigns = array();
      foreach($resultCollectCampaign as $campaign) {

         $campaignId = $campaign['id'];
         
         $o_CollectContent = new PluginFusioninventoryCollectcontent();
         $result = $o_CollectContent->find('plugin_fusioninventory_collects_id = '.$campaignId);

         $o_RegKey = new PluginFusioninventoryCollectregistrykey();
         
         if (count($result) == 0) 
            continue;
      
         $registryKeys = array();
         foreach($result as $row) {

            $resultRegistry = $o_RegKey->find('computers_id = '.$computers_id.' AND 
                                            glpi_plugin_fusioninventory_collectcontents_id = '.
                                            $row['id']);

            if (count($resultRegistry) == 0) continue;

            foreach($resultRegistry as $rowReg) 
               $registryKeys[] = $rowReg;

         }


         $campaigns[$campaignId] = $registryKeys;
      }

      if(count($campaigns) === 0) 
         return false;

      echo '<table class="tab_cadre_fixe" style="margin: 0; margin-top: 5px;">';

      foreach($campaigns as $cId => $campaign) {
         
         $collectObject->getFromDB($cId);

         echo '<tr class="tab_bg_1">';
         echo '<th colspan="3">'.$LANG['plugin_fusioninventory']['collect'][3].' : ';
         echo $collectObject->fields['name'].'</th>';
         echo '</tr>';

         echo '<tr class="tab_bg_1">';
         echo '<th>'.$LANG['plugin_fusioninventory']['collect']['fields'][1].'</th>';
         echo '<th>'.$LANG['rulesengine'][13].'</th>';
         echo '</tr>';

         foreach ($campaign as $key) {

            if(empty($key['value'])) {
               $key['value'] = $LANG['plugin_fusioninventory']['collect'][4];
            }

            $o_CollectContent->getFromDB($key['glpi_plugin_fusioninventory_collectcontents_id']);
            $details = json_decode($o_CollectContent->fields['details']);
            echo '<tr class="tab_bg_1">';
            echo '<td><em style="font-weight:bold;"><acronym title="HKEY_LOCAL_MACHINE/';
            echo $details->path.'">'.$key['name'];
            echo '</acronym></em></td>';
            echo '<td><em style="font-weight:bold;">'.$key['value'].'</em></td>';
            echo '</tr>';
         }

      }

      echo "</table>";
   }
}

?>